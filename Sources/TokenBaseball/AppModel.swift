import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = GameState()
    @Published var errorMessage: String?
    @Published private(set) var loadError: String?
    @Published private(set) var isImporting = false
    @Published private(set) var importMessage: String?
    private var store: GameStore?
    private var importTask: Task<[UsageSnapshot], Error>?
    let saveURL: URL

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--data-directory"), arguments.indices.contains(index + 1) {
            saveURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).appendingPathComponent("state.json")
        } else {
            saveURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TokenBaseball/state.json")
        }
        load()
    }

    func load() {
        do {
            let loaded = try GameStore(persistence: JSONDiskPersistence(url: saveURL))
            store = loaded
            state = loaded.state
            loadError = nil
        } catch {
            store = nil
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func perform(_ action: (GameStore) throws -> Void) -> Bool {
        guard let store else { return false }
        errorMessage = nil
        do {
            try action(store)
            state = store.state
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshUsage() {
        guard !isImporting, let store else { return }
        let folders = state.importFolders
        guard !folders.isEmpty else {
            errorMessage = "설정에서 Codex 또는 Claude Code의 기록 폴더를 먼저 연결해 주세요."
            return
        }
        isImporting = true
        importMessage = nil
        let reader = Task.detached(priority: .userInitiated) {
            var result: [UsageSnapshot] = []
            if let path = folders["codex"] {
                result += try CodexUsageImporter().read(folder: URL(fileURLWithPath: path))
            }
            if let path = folders["claude"] {
                result += try ClaudeUsageImporter().read(folder: URL(fileURLWithPath: path))
            }
            try Task.checkCancellation()
            return result
        }
        importTask = reader
        Task {
            defer {
                isImporting = false
                importTask = nil
            }
            do {
                let snapshots = try await reader.value
                guard !reader.isCancelled else { throw CancellationError() }
                guard !snapshots.isEmpty else {
                    importMessage = "연결한 폴더에서 사용량 기록을 찾지 못했어요. 설정에서 기록 폴더를 확인해 주세요."
                    return
                }
                let previousBalance = store.state.earnedCurrency
                let added = try store.importUsage(snapshots)
                state = store.state
                importMessage = added == 0 ? "이미 반영한 기록이에요. 새로 추가된 사용량이 없어요."
                    : "\(added.formatted())토큰을 반영하고 \((state.earnedCurrency - previousBalance).formatted())볼을 받았어요."
            } catch is CancellationError {
                importMessage = "사용량 반영을 취소했어요. 기존 기록과 잔액은 유지됩니다."
            } catch {
                errorMessage = error.localizedDescription
                importMessage = "사용량 반영에 실패했어요. 기존 기록과 잔액은 유지됩니다."
            }
        }
    }

    func cancelImport() { importTask?.cancel() }

    func connectDefault(source: String) {
        let name = source == "codex" ? ".codex" : ".claude"
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        connect(folder: folder, source: source)
    }

    func chooseFolder(source: String) {
        let panel = NSOpenPanel()
        panel.title = "\(source == "codex" ? "Codex" : "Claude Code") 사용 기록 폴더"
        panel.prompt = "연결"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url { connect(folder: url, source: source) }
    }

    private func connect(folder: URL, source: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "기록 폴더를 찾지 못했어요. ‘폴더 선택’으로 실제 사용 기록이 있는 폴더를 연결해 주세요."
            return
        }
        perform { try $0.setImportFolder(folder.path, for: source) }
    }

    func card(_ id: UUID) -> PlayerCard? { state.cards.first { $0.id == id } }
    func assignedPosition(_ id: UUID) -> FieldPosition? {
        FieldPosition.allCases.first { state.lineup[$0.rawValue] == id }
    }
}
