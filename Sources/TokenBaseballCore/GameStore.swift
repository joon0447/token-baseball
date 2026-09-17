import Foundation

/// Mutations become visible only after their complete snapshot is saved successfully.
public final class GameStore {
    public private(set) var state: GameState
    private let persistence: any SnapshotPersistence
    let randomIndex: (Int) -> Int

    public init(persistence: any SnapshotPersistence,
                randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) throws {
        self.persistence = persistence
        self.randomIndex = randomIndex
        if let initial = try persistence.load() {
            try initial.validate()
            self.state = initial
        } else {
            var initial = GameState()
            PlayerGenerator.grantStarters(to: &initial, randomIndex: randomIndex)
            try initial.validate()
            try persistence.save(initial)
            self.state = initial
        }
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
