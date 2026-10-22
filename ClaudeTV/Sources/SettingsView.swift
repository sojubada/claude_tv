import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore

    @AppStorage(SettingsKey.apiKey) private var apiKey = ""
    @AppStorage(SettingsKey.model) private var model = Defaults.model
    @AppStorage(SettingsKey.systemPrompt) private var systemPrompt = Defaults.systemPrompt
    @AppStorage(SettingsKey.maxTokens) private var maxTokens = Defaults.maxTokens
    @AppStorage(SettingsKey.fontSize) private var fontSize = Defaults.fontSize
    @AppStorage(SettingsKey.webSearch) private var webSearch = false

    @State private var models: [ModelInfo] = AnthropicClient.fallbackModels
    @State private var status = ""
    @State private var checking = false
    @State private var confirmDeleteAll = false

    private let fontSizes: [(String, Double)] = [("작게", 28), ("보통", 34), ("크게", 40), ("아주 크게", 46)]
    private let tokenOptions: [(String, Int)] = [("짧게 (2,000)", 2048), ("보통 (4,000)", 4096),
                                                 ("길게 (8,000)", 8192), ("아주 길게 (16,000)", 16000)]

    private var modelChoices: [ModelInfo] {
        models.contains(where: { $0.id == model })
            ? models
            : [ModelInfo(id: model, displayName: model)] + models
    }

    var body: some View {
        Form {
            Section(header: Text("API 키"),
                    footer: Text("Claude Console(console.anthropic.com)에서 발급한 키를 붙여넣으세요. 아이폰의 Apple TV 리모컨 키보드로 붙여넣으면 편합니다. 사용량만큼 API 요금이 청구됩니다.")) {
                SecureField("sk-ant-로 시작하는 키", text: $apiKey)
                Text(keySummary)
                    .foregroundColor(.secondary)
                Button(checking ? "확인 중…" : "연결 확인 및 모델 목록 불러오기") {
                    checkConnection()
                }
                .disabled(checking || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if !status.isEmpty {
                    Text(status)
                        .foregroundColor(status.hasPrefix("✅") ? .green : Theme.accent)
                }
            }

            Section(header: Text("답변")) {
                Picker("모델", selection: $model) {
                    ForEach(modelChoices) { info in
                        Text(info.displayName == info.id ? info.id : "\(info.displayName)  (\(info.id))")
                            .tag(info.id)
                    }
                }
                Picker("최대 답변 길이", selection: $maxTokens) {
                    ForEach(tokenOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Toggle("웹 검색 사용", isOn: $webSearch)
            }

            Section(header: Text("화면")) {
                Picker("글자 크기", selection: $fontSize) {
                    ForEach(fontSizes, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Text("미리보기: 이 크기로 답변이 표시됩니다.")
                    .font(.system(size: fontSize))
            }

            Section(header: Text("시스템 프롬프트"),
                    footer: Text("모든 대화에 공통으로 적용되는 지시입니다.")) {
                TextField("시스템 프롬프트", text: $systemPrompt)
                Button("기본값으로 되돌리기") { systemPrompt = Defaults.systemPrompt }
            }

            Section(header: Text("데이터")) {
                Button("모든 대화 삭제") { confirmDeleteAll = true }
                Text("Claude TV \(appVersion)")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("설정")
        .alert("모든 대화를 삭제할까요?", isPresented: $confirmDeleteAll) {
            Button("삭제", role: .destructive) { store.deleteAll() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 대화는 되돌릴 수 없습니다.")
        }
    }

    private var keySummary: String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "키가 아직 입력되지 않았습니다." }
        return "입력됨 · …\(key.suffix(4)) (\(key.count)자)"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }

    private func checkConnection() {
        checking = true
        status = ""
        let client = AnthropicClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            do {
                let list = try await client.listModels()
                let claude = list.filter { $0.id.hasPrefix("claude") }
                if !claude.isEmpty { models = claude }
                status = "✅ 연결 성공 · 사용 가능한 모델 \(claude.count)개"
            } catch {
                status = "⚠️ " + error.localizedDescription
            }
            checking = false
        }
    }
}
