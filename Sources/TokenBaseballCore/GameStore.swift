import Foundation

/// Mutations become visible only after their complete snapshot is saved successfully.
public final class GameStore {
    public private(set) var state: GameState
    private let persistence: any SnapshotPersistence

    public init(persistence: any SnapshotPersistence) throws {
        self.persistence = persistence
        let initial = try persistence.load() ?? GameState()
        try initial.validate()
        self.state = initial
    }

    public func setImportFolder(_ path: String, for source: String) throws {
        guard ["codex", "claude"].contains(source), (path as NSString).isAbsolutePath else { throw GameError.invalidFolder }
        var candidate = state
        candidate.importFolders[source] = path
        try commit(candidate)
    }

    func commit(_ candidate: GameState) throws {
        try candidate.validate()
        try persistence.save(candidate)
        state = candidate
    }
}
