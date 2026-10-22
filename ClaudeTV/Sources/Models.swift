import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: ChatRole
    var text: String
    /// Error notices are shown in the chat but never sent back to the API.
    var isError = false
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "새 대화"
    var messages: [ChatMessage] = []
    var updatedAt = Date()
}

/// One block of rendered text. Each block is focusable on its own so the
/// Siri Remote can step through a long answer piece by piece.
struct TextBlock: Identifiable {
    enum Kind {
        case paragraph
        case heading
        case code
    }

    let id: String
    let kind: Kind
    let text: String
}

enum BlockSplitter {
    /// Splits a message into paragraphs, headings and code chunks.
    static func blocks(for text: String, messageID: UUID) -> [TextBlock] {
        var result: [TextBlock] = []
        var index = 0

        func add(_ kind: TextBlock.Kind, _ body: String) {
            let trimmed = kind == .code ? body : body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(TextBlock(id: "\(messageID.uuidString)-\(index)", kind: kind, text: trimmed))
            index += 1
        }

        func addProse(_ prose: String) {
            for chunk in prose.components(separatedBy: "\n\n") {
                let line = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("#") {
                    let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    add(.heading, heading)
                } else {
                    add(.paragraph, chunk)
                }
            }
        }

        let parts = text.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            if i % 2 == 0 {
                addProse(part)
            } else {
                // Drop the language tag on the fence line.
                var lines = part.components(separatedBy: "\n")
                if let first = lines.first, !first.contains(" ") { lines.removeFirst() }
                while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
                // Keep code chunks short enough to fit on screen.
                stride(from: 0, to: lines.count, by: 14).forEach { start in
                    let end = min(start + 14, lines.count)
                    add(.code, lines[start..<end].joined(separator: "\n"))
                }
            }
        }

        if result.isEmpty {
            result.append(TextBlock(id: "\(messageID.uuidString)-0", kind: .paragraph, text: text))
        }
        return result
    }
}
