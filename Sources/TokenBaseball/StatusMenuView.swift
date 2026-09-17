import AppKit
import SwiftUI
import TokenBaseballCore

struct StatusMenuView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("오늘 \(model.todayTokens.formatted()) 토큰")
        Text("누적 \(TokenDisplay.short(model.state.totalTokens)) 토큰")
        Text("뽑기 카드 \(model.state.availableDraws.formatted())장")
        if let date = model.state.lastImport {
            Text("최근 반영 \(date.formatted(date: .omitted, time: .shortened))")
        }
        if model.state.importFolders.isEmpty { Text("사용 기록 미연결") }
        if model.loadError != nil { Text("저장 데이터를 확인해 주세요") }
        Divider()
        if model.isImporting {
            Button("사용량 반영 취소", action: model.cancelImport)
        } else {
            Button("지금 사용량 반영", action: model.refreshUsage)
                .disabled(model.state.importFolders.isEmpty || model.loadError != nil)
        }
        Button("TokenBaseball 열기") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("종료") { NSApplication.shared.terminate(nil) }
    }
}
