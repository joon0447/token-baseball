import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct TokenBaseballApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("TokenBaseball") {
            ContentView().frame(minWidth: 880, minHeight: 620)
        }
        .defaultSize(width: 1100, height: 760)
    }
}

enum AppPage: String, CaseIterable, Identifiable {
    case home = "홈", shop = "카드 상점", collection = "보유 카드", roster = "내 선수단", settings = "설정"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "house"
        case .shop: "cart"
        case .collection: "rectangle.stack"
        case .roster: "baseball.diamond.bases"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var page: AppPage? = .home
    var body: some View {
        NavigationSplitView {
            List(AppPage.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("TokenBaseball")
        } detail: {
            ContentUnavailableView((page ?? .home).rawValue, systemImage: (page ?? .home).symbol,
                                   description: Text("AI 사용 기록으로 나만의 야구단을 만들어 보세요."))
        }
    }
}
