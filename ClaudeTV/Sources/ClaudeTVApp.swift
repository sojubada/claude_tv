import SwiftUI

@main
struct ClaudeTVApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let userBubble = Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.28)
    static let assistantBubble = Color.white.opacity(0.07)
    static let focusRing = Color.white.opacity(0.9)
}
