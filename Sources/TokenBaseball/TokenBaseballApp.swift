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
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("TokenBaseball") {
            ContentView().environmentObject(model).frame(minWidth: 880, minHeight: 620)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("사용량 반영", action: model.refreshUsage)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isImporting || model.loadError != nil)
            }
        }
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
    @EnvironmentObject private var model: AppModel
    @State private var page: AppPage? = .home
    var body: some View {
        Group {
            if let loadError = model.loadError {
                ContentUnavailableView {
                    Label("저장 데이터를 열 수 없어요", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(loadError + "\n" + model.saveURL.path)
                } actions: {
                    Button("다시 읽기", action: model.load)
                    Button("저장 폴더 보기") { NSWorkspace.shared.open(model.saveURL.deletingLastPathComponent()) }
                }
            } else {
                navigation
            }
        }
        .alert("작업을 완료하지 못했어요", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var navigation: some View {
        NavigationSplitView {
            List(AppPage.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("TokenBaseball")
        } detail: {
            Group {
                switch page ?? .home {
                case .home: HomeView { page = $0 }
                case .shop: ShopView()
                case .collection: ContentUnavailableView("보유 카드", systemImage: "rectangle.stack")
                case .roster: ContentUnavailableView("내 선수단", systemImage: "baseball.diamond.bases")
                case .settings: SettingsView()
                }
            }
            .navigationTitle((page ?? .home).rawValue)
            .toolbar {
                ToolbarItem {
                    Text("\(model.state.balance.formatted())볼").monospacedDigit()
                        .accessibilityLabel("보유 재화 \(model.state.balance)볼")
                }
            }
        }
    }
}
