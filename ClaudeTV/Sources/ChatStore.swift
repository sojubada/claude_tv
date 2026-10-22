import Foundation
import SwiftUI

enum SettingsKey {
    static let apiKey = "apiKey"
    static let model = "model"
    static let systemPrompt = "systemPrompt"
    static let maxTokens = "maxTokens"
    static let fontSize = "fontSize"
    static let webSearch = "webSearch"
}

enum Defaults {
    static let model = "claude-sonnet-5-5"
    static let maxTokens = 4096
    static let fontSize = 34.0
    static let systemPrompt = """
    당신은 Apple TV 화면에 표시되는 대화 도우미입니다. 사용자는 약 3미터 떨어진 소파에서 55인치 TV로 답변을 읽습니다. \
    한국어 존댓말로 답하고, 넓은 표나 긴 코드 대신 짧은 문단과 목록 위주로 간결하게 정리해 주세요.
    """
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var streamingConversationID: UUID?

    private var streamTask: Task<Void, Never>?
    private let fileURL: URL

    init() {
        fileURL = Self.storageDirectory().appendingPathComponent("conversations.json")
        load()
    }

    // MARK: Storage

    /// tvOS may refuse Application Support, so fall back to Caches.
    private static func storageDirectory() -> URL {
        let fm = FileManager.default
        for dir in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
            if let url = fm.urls(for: dir, in: .userDomainMask).first?.appendingPathComponent("ClaudeTV") {
                if (try? fm.createDirectory(at: url, withIntermediateDirectories: true)) != nil {
                    return url
                }
            }
        }
        return fm.temporaryDirectory
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = saved.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Conversations

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    @discardableResult
    func newConversation() -> UUID {
        // Reuse an existing empty conversation instead of piling up blanks.
        if let empty = conversations.first(where: { $0.messages.isEmpty }) {
            return empty.id
        }
        let conv = Conversation()
        conversations.insert(conv, at: 0)
        save()
        return conv.id
    }

    func delete(_ id: UUID) {
        if streamingConversationID == id { stop() }
        conversations.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        stop()
        conversations.removeAll()
        save()
    }

    private func update(_ id: UUID, _ change: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[i])
    }

    // MARK: Sending

    var isStreaming: Bool { streamingConversationID != nil }

    func send(_ text: String, in id: UUID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        let defaults = UserDefaults.standard
        let apiKey = (defaults.string(forKey: SettingsKey.apiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = defaults.string(forKey: SettingsKey.model) ?? Defaults.model
        let system = defaults.string(forKey: SettingsKey.systemPrompt) ?? Defaults.systemPrompt
        let storedMax = defaults.integer(forKey: SettingsKey.maxTokens)
        let maxTokens = storedMax > 0 ? storedMax : Defaults.maxTokens
        let webSearch = defaults.bool(forKey: SettingsKey.webSearch)

        let reply = ChatMessage(role: .assistant, text: "")
        update(id) { conv in
            if conv.messages.isEmpty {
                conv.title = String(text.prefix(40))
            }
            conv.messages.append(ChatMessage(role: .user, text: text))
            conv.messages.append(reply)
            conv.updatedAt = Date()
        }
        moveToTop(id)
        save()

        guard !apiKey.isEmpty else {
            finishWithError("API 키가 없습니다. 설정에서 Claude Console API 키를 입력해 주세요.", conversation: id, reply: reply.id)
            return
        }

        let history = conversation(id)?.messages.filter { $0.id != reply.id } ?? []
        let client = AnthropicClient(apiKey: apiKey)
        streamingConversationID = id

        streamTask = Task { [weak self] in
            do {
                let stream = client.stream(model: model, system: system, messages: history,
                                           maxTokens: maxTokens, webSearch: webSearch)
                for try await piece in stream {
                    // stop() has already tidied up a cancelled stream.
                    if Task.isCancelled { return }
                    self?.appendText(piece, conversation: id, reply: reply.id)
                }
                if Task.isCancelled { return }
                self?.finish(conversation: id)
            } catch {
                if Task.isCancelled { return }
                self?.finishWithError(error.localizedDescription, conversation: id, reply: reply.id)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        if let id = streamingConversationID { finish(conversation: id) }
    }

    private func appendText(_ piece: String, conversation id: UUID, reply: UUID) {
        update(id) { conv in
            if let i = conv.messages.firstIndex(where: { $0.id == reply }) {
                conv.messages[i].text += piece
            }
        }
    }

    private func finish(conversation id: UUID) {
        update(id) { conv in
            // Drop a reply that never received any text.
            conv.messages.removeAll { $0.role == .assistant && !$0.isError && $0.text.isEmpty }
            conv.updatedAt = Date()
        }
        streamingConversationID = nil
        streamTask = nil
        save()
    }

    private func finishWithError(_ message: String, conversation id: UUID, reply: UUID) {
        update(id) { conv in
            if let i = conv.messages.firstIndex(where: { $0.id == reply }) {
                if conv.messages[i].text.isEmpty {
                    conv.messages[i].text = "⚠️ " + message
                    conv.messages[i].isError = true
                } else {
                    conv.messages.append(ChatMessage(role: .assistant, text: "⚠️ " + message, isError: true))
                }
            }
        }
        finish(conversation: id)
    }

    private func moveToTop(_ id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }), i != 0 else { return }
        let conv = conversations.remove(at: i)
        conversations.insert(conv, at: 0)
    }
}
