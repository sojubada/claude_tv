import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let displayName: String
}

struct AnthropicClient {
    var baseURL = URL(string: "https://api.anthropic.com")!
    let apiKey: String

    static let fallbackModels = [
        ModelInfo(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5"),
        ModelInfo(id: "claude-opus-5-5", displayName: "Claude Opus 5.5"),
        ModelInfo(id: "claude-haiku-5-5", displayName: "Claude Haiku 5.5"),
    ]

    private func request(path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 300
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        return req
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return "HTTP \(status): \(msg)"
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        return "HTTP \(status): \(body.prefix(300))"
    }

    /// Lists the models this API key can use.
    func listModels() async throws -> [ModelInfo] {
        var req = request(path: "v1/models")
        req.url = URL(string: baseURL.absoluteString + "/v1/models?limit=100")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw APIError(message: Self.errorMessage(from: data, status: status))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["data"] as? [[String: Any]] else {
            throw APIError(message: "모델 목록을 읽을 수 없습니다.")
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return ModelInfo(id: id, displayName: (item["display_name"] as? String) ?? id)
        }
    }

    /// Sends the conversation and yields text as it streams in.
    func stream(model: String,
                system: String,
                messages: [ChatMessage],
                maxTokens: Int,
                webSearch: Bool) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = request(path: "v1/messages", method: "POST")
                    var body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "messages": Self.apiMessages(from: messages),
                    ]
                    if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        body["system"] = system
                    }
                    if webSearch {
                        body["tools"] = [[
                            "type": "web_search_20250305",
                            "name": "web_search",
                            "max_uses": 5,
                        ]]
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw APIError(message: Self.errorMessage(from: data, status: status))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = json.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "content_block_start":
                            // Separate text that comes after a web search from the text before it.
                            if let block = event["content_block"] as? [String: Any],
                               block["type"] as? String == "server_tool_use" {
                                continuation.yield("\n\n🔎 웹 검색 중…\n\n")
                            }
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any],
                               delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            if let delta = event["delta"] as? [String: Any],
                               delta["stop_reason"] as? String == "max_tokens" {
                                continuation.yield("\n\n(최대 출력 길이에 도달해 답변이 잘렸습니다)")
                            }
                        case "error":
                            let err = event["error"] as? [String: Any]
                            throw APIError(message: (err?["message"] as? String) ?? "알 수 없는 스트리밍 오류")
                        case "message_stop":
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Converts stored messages into API turns: drops error notices and empty
    /// replies, and merges consecutive turns from the same role.
    static func apiMessages(from messages: [ChatMessage]) -> [[String: String]] {
        var turns: [(role: ChatRole, text: String)] = []
        for m in messages where !m.isError {
            let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = turns.last, last.role == m.role {
                turns[turns.count - 1].text += "\n\n" + text
            } else {
                turns.append((m.role, text))
            }
        }
        // The API expects the conversation to start with the user.
        while let first = turns.first, first.role != .user { turns.removeFirst() }
        return turns.map { ["role": $0.role.rawValue, "content": $0.text] }
    }
}
