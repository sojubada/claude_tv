import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ChatStore
    @AppStorage(SettingsKey.apiKey) private var apiKey = ""
    @State private var selection: UUID?
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header

                    if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("먼저 설정에서 Claude Console API 키를 입력해 주세요.")
                            .font(.headline)
                            .foregroundColor(Theme.accent)
                    }

                    HStack(spacing: 40) {
                        Button {
                            let id = store.newConversation()
                            DispatchQueue.main.async { selection = id }
                        } label: {
                            Label("새 대화", systemImage: "plus.bubble")
                        }

                        NavigationLink(isActive: $showSettings) {
                            SettingsView()
                        } label: {
                            Label("설정", systemImage: "gearshape")
                        }
                    }

                    if store.conversations.isEmpty {
                        Text("아직 대화가 없습니다. '새 대화'를 눌러 시작하세요.")
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        Text("최근 대화")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.top, 20)

                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(store.conversations) { conv in
                                NavigationLink(tag: conv.id, selection: $selection) {
                                    ChatView(conversationID: conv.id)
                                } label: {
                                    ConversationRow(conversation: conv,
                                                    isStreaming: store.streamingConversationID == conv.id)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(conv.id)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Image(systemName: "sparkles")
                .foregroundColor(Theme.accent)
            Text("Claude TV")
                .font(.system(size: 64, weight: .bold))
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isStreaming: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 a h:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(preview)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 8) {
                Text(Self.formatter.string(from: conversation.updatedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isStreaming {
                    Text("답변 중…")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: String {
        guard let last = conversation.messages.last(where: { !$0.text.isEmpty }) else { return "빈 대화" }
        return last.text.replacingOccurrences(of: "\n", with: " ")
    }
}
