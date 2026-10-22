import SwiftUI

struct ChatView: View {
    let conversationID: UUID

    @EnvironmentObject private var store: ChatStore
    @AppStorage(SettingsKey.fontSize) private var fontSize = Defaults.fontSize
    @AppStorage(SettingsKey.model) private var model = Defaults.model
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var conversation: Conversation? { store.conversation(conversationID) }
    private var messages: [ChatMessage] { conversation?.messages ?? [] }
    private var isStreamingHere: Bool { store.streamingConversationID == conversationID }

    /// Changes whenever new text arrives, so the view can follow the answer.
    private var scrollSignal: Int {
        messages.count * 1_000_000 + (messages.last?.text.count ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        if messages.isEmpty {
                            emptyState
                        }
                        ForEach(messages) { message in
                            MessageView(message: message,
                                        fontSize: fontSize,
                                        isPending: isStreamingHere && message.id == messages.last?.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
                .onChange(of: scrollSignal) { _ in
                    if isStreamingHere {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            inputBar
        }
        .navigationTitle(conversation?.title ?? "대화")
        .onAppear {
            if messages.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { inputFocused = true }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("무엇이든 물어보세요")
                .font(.system(size: fontSize * 1.4, weight: .semibold))
            Text("아래 입력창을 선택하면 키보드가 열립니다. 아이폰 키보드나 블루투스 키보드로도 입력할 수 있습니다.")
                .font(.system(size: fontSize * 0.8))
                .foregroundColor(.secondary)
            Text("모델: \(model)")
                .font(.system(size: fontSize * 0.7))
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }

    private var inputBar: some View {
        HStack(spacing: 30) {
            TextField(isStreamingHere ? "답변을 받는 중입니다…" : "메시지를 입력하세요", text: $draft)
                .focused($inputFocused)
                .onSubmit(send)
                .disabled(isStreamingHere)

            if isStreamingHere {
                Button { store.stop() } label: {
                    Label("중지", systemImage: "stop.circle")
                }
            } else {
                Button(action: send) {
                    Label("보내기", systemImage: "paperplane")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isStreaming)
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.35))
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !store.isStreaming else { return }
        draft = ""
        store.send(text, in: conversationID)
    }
}

// MARK: - Message

struct MessageView: View {
    let message: ChatMessage
    let fontSize: Double
    let isPending: Bool

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 300) }
            VStack(alignment: .leading, spacing: 18) {
                Text(isUser ? "나" : "Claude")
                    .font(.system(size: fontSize * 0.65, weight: .semibold))
                    .foregroundColor(isUser ? Theme.accent : .secondary)

                if message.text.isEmpty && isPending {
                    TextBlockView(block: TextBlock(id: message.id.uuidString, kind: .paragraph, text: "생각 중…"),
                                  fontSize: fontSize, dimmed: true)
                } else {
                    ForEach(BlockSplitter.blocks(for: message.text, messageID: message.id)) { block in
                        TextBlockView(block: block, fontSize: fontSize, dimmed: message.isError)
                    }
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isUser ? Theme.userBubble : Theme.assistantBubble)
            )
            if !isUser { Spacer(minLength: 120) }
        }
    }
}

// MARK: - Block

/// A focusable chunk of text. Focus is what lets the Siri Remote scroll
/// through long answers, so every block can take it.
struct TextBlockView: View {
    let block: TextBlock
    let fontSize: Double
    var dimmed = false

    @FocusState private var focused: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(focused ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Theme.focusRing : Color.clear, lineWidth: 3)
            )
            .focusable(true)
            .focused($focused)
            .animation(.easeOut(duration: 0.15), value: focused)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading:
            Text(Self.render(block.text))
                .font(.system(size: fontSize * 1.15, weight: .bold))
        case .code:
            Text(block.text)
                .font(.system(size: fontSize * 0.75, design: .monospaced))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.45))
                .cornerRadius(10)
        case .paragraph:
            Text(Self.render(block.text))
                .font(.system(size: fontSize))
                .foregroundColor(dimmed ? .secondary : .primary)
                .lineSpacing(fontSize * 0.25)
        }
    }

    /// Inline markdown (bold, italic, code, links) with bullets made readable.
    static func render(_ text: String) -> AttributedString {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.drop(while: { $0 == " " })
            let indent = String(repeating: "    ", count: (line.count - trimmed.count) / 2)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return indent + "• " + trimmed.dropFirst(2)
            }
            if trimmed.hasPrefix(">") {
                return indent + "▎" + trimmed.dropFirst().drop(while: { $0 == " " })
            }
            return line
        }
        let joined = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: joined, options: options)) ?? AttributedString(joined)
    }
}
