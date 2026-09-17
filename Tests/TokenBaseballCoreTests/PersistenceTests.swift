import Foundation
import XCTest
@testable import TokenBaseballCore

final class MemoryPersistence: SnapshotPersistence {
    var snapshot: GameState?
    var shouldFail = false
    var saveCount = 0
    init(snapshot: GameState? = nil) { self.snapshot = snapshot }
    func load() throws -> GameState? { snapshot }
    func save(_ state: GameState) throws {
        if shouldFail { throw TestFailure.diskUnavailable }
        snapshot = state
        saveCount += 1
    }
}
enum TestFailure: Error { case diskUnavailable }

final class PersistenceTests: XCTestCase {
    func testFreshStoreGrantsNineStableStartersExactlyOnce() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk, randomIndex: { _ in 0 })
        XCTAssertEqual(store.state.cards.count, 9)
        XCTAssertEqual(store.state.lineup.count, 9)
        XCTAssertEqual(Set(store.state.cards.map(\.name)).count, 9)
        XCTAssertEqual(Set(store.state.cards.map(\.position)), Set(FieldPosition.allCases))
        XCTAssertTrue(store.state.cards.allSatisfy { $0.tier == .rookie && $0.origin == .starter })
        XCTAssertTrue(store.state.starterGrantComplete)
        XCTAssertEqual(store.state.totalTokens, 0)
        XCTAssertEqual(store.state.availableDraws, 0)
        XCTAssertEqual(disk.saveCount, 1)
        let reopened = try GameStore(persistence: disk, randomIndex: { $0 - 1 })
        XCTAssertEqual(reopened.state, store.state)
        XCTAssertEqual(disk.saveCount, 1)
    }

    func testFreshGrantFailureDoesNotPersistPartialTeam() {
        let disk = MemoryPersistence()
        disk.shouldFail = true
        XCTAssertThrowsError(try GameStore(persistence: disk))
        XCTAssertNil(disk.snapshot)
        XCTAssertEqual(disk.saveCount, 0)
    }

    func testFolderSettingsPersistAndRollbackOnFailure() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        try store.setImportFolder("/tmp/codex", for: "codex")
        try store.setImportFolder("/tmp/claude", for: "claude")
        XCTAssertEqual(try GameStore(persistence: disk).state.importFolders, ["codex": "/tmp/codex", "claude": "/tmp/claude"])
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.setImportFolder("/tmp/new", for: "codex"))
        XCTAssertEqual(store.state, before)
        XCTAssertThrowsError(try store.setImportFolder("relative", for: "claude"))
        XCTAssertThrowsError(try store.setImportFolder("/tmp", for: "unknown"))
    }

    func testJSONRoundTripPreservesNamesPhotosUsageAndDraws() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JSONDiskPersistence(url: directory.appendingPathComponent("state.json"))
        let store = try GameStore(persistence: disk)
        let id = store.state.cards[0].id
        try store.rename(cardID: id, name: "내 에이스")
        try store.setPhoto(cardID: id, data: Data([1, 2, 3]))
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 100_000_000,
                                         dailyTokens: ["2026-09-17": 10_000_000])])
        _ = try store.openDraw()
        let restarted = try GameStore(persistence: JSONDiskPersistence(url: disk.url))
        XCTAssertEqual(restarted.state, store.state)
        XCTAssertEqual(restarted.state.tokens(on: "2026-09-17"), 10_000_000)
    }

    func testV1MigrationBacksUpOriginalAndGrantsOnlyOnce() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        let pitcher = PlayerCard(catalogID: "rookie-pitcher", defaultName: "강도윤", customName: "기존 에이스",
                                 tier: .rookie, position: .pitcher, photoData: Data([7, 8]))
        let catcher = PlayerCard(catalogID: "allStar-catcher", defaultName: "신도현", tier: .allStar, position: .catcher)
        let original = try legacyData(cards: [pitcher, catcher], lineup: ["pitcher": pitcher.id, "secondBase": catcher.id])
        try original.write(to: url)
        let store = try GameStore(persistence: JSONDiskPersistence(url: url))
        XCTAssertEqual(store.state.schemaVersion, 2)
        XCTAssertEqual(store.state.cards.count, 11)
        XCTAssertEqual(store.state.cards.filter { $0.origin == .starter }.count, 9)
        XCTAssertEqual(store.state.cards.filter { $0.origin == .legacy }.count, 2)
        XCTAssertEqual(store.state.cards.filter { $0.id != pitcher.id && $0.id != catcher.id }.filter { $0.tier == .rookie }.count, 9)
        XCTAssertEqual(store.state.cards.first { $0.id == pitcher.id }, pitcher)
        XCTAssertEqual(store.state.cards.first { $0.id == catcher.id }, catcher)
        XCTAssertEqual(store.state.lineup["pitcher"], pitcher.id)
        XCTAssertNotEqual(store.state.lineup["secondBase"], catcher.id)
        XCTAssertEqual(store.state.lineup.count, 9)
        XCTAssertEqual(store.state.totalTokens, 100_000_000)
        XCTAssertEqual(store.state.availableDraws, 2)
        XCTAssertTrue(store.state.sourceDailyTotals.isEmpty)
        XCTAssertEqual(store.state.tokens(on: "2026-09-17"), 0)
        XCTAssertEqual(store.state.importFolders, ["codex": "/tmp/codex"])
        let backup = url.appendingPathExtension("v1.backup")
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let restarted = try GameStore(persistence: JSONDiskPersistence(url: url))
        XCTAssertEqual(restarted.state, store.state)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        // Restoring an older v1 file must not replace the first migration backup.
        let replacement = try legacyData(cards: [], lineup: [:])
        try replacement.write(to: url, options: .atomic)
        _ = try GameStore(persistence: JSONDiskPersistence(url: url))
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testCorruptUnknownAndInvalidV1FilesRemainUntouched() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        let invalidV1 = try legacyData(cards: [], lineup: [:], earned: 99)
        for bytes in [Data("broken".utf8), Data("{\"schemaVersion\":99}".utf8), invalidV1] {
            try bytes.write(to: url, options: .atomic)
            let disk = JSONDiskPersistence(url: url)
            XCTAssertThrowsError(try GameStore(persistence: disk))
            let valid = try GameStore(persistence: MemoryPersistence()).state
            XCTAssertThrowsError(try disk.save(valid))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("v1.backup").path))
        }
    }

    func testStrictJSONCountersRejectFractionsBooleansAndHugeLiterals() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        _ = try GameStore(persistence: JSONDiskPersistence(url: url))
        let original = try String(contentsOf: url, encoding: .utf8)
        for literal in ["true", "1.5", "9007199254740993.1", "9223372036854775808"] {
            let changed = original.replacingOccurrences(of: "\"totalTokens\" : 0", with: "\"totalTokens\" : " + literal)
            XCTAssertNotEqual(changed, original)
            let bytes = Data(changed.utf8)
            try bytes.write(to: url, options: .atomic)
            XCTAssertThrowsError(try JSONDiskPersistence(url: url).load())
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testStaleWriterAndExternallyCorruptedFileCannotOverwrite() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = try GameStore(persistence: JSONDiskPersistence(url: url))
        let second = try GameStore(persistence: JSONDiskPersistence(url: url))
        let before = second.state
        _ = try first.importUsage([.init(sourceID: "codex:a", totalTokens: 50_000_000)])
        let latest = try Data(contentsOf: url)
        XCTAssertThrowsError(try second.importUsage([.init(sourceID: "claude:b", totalTokens: 30_000_000)])) {
            XCTAssertEqual($0 as? GameError, .staleSave)
        }
        XCTAssertEqual(second.state, before)
        XCTAssertEqual(try Data(contentsOf: url), latest)
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: url, options: .atomic)
        let firstBefore = first.state
        XCTAssertThrowsError(try first.setImportFolder("/tmp/codex", for: "codex"))
        XCTAssertEqual(first.state, firstBefore)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testMissingGrantDuplicateCardsAndMismatchedLineupAreRejected() throws {
        var state = try GameStore(persistence: MemoryPersistence()).state
        state.starterGrantComplete = false
        XCTAssertThrowsError(try state.validate())
        state.starterGrantComplete = true
        state.cards.append(state.cards[0])
        XCTAssertThrowsError(try state.validate())
        state.cards.removeLast()
        state.lineup["catcher"] = state.cards[0].id
        XCTAssertThrowsError(try state.validate())
    }

    func testDrawOriginCountRejectsLostCardsAndCounterRollbackOnSaveAndLoad() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let disk = JSONDiskPersistence(url: url)
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "s", totalTokens: 100_000_000)])
        let drawnID = try store.openDraw()
        XCTAssertEqual(store.state.cards.first { $0.id == drawnID }?.origin, .draw)
        let original = try Data(contentsOf: url)
        var missingCard = store.state
        missingCard.cards.removeAll { $0.id == drawnID }
        var rolledBackCount = store.state
        rolledBackCount.openedDraws = 0
        for invalid in [missingCard, rolledBackCount] {
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertThrowsError(try disk.save(invalid))
            XCTAssertEqual(try Data(contentsOf: url), original)
            let bytes = try JSONEncoder().encode(invalid)
            try bytes.write(to: url, options: .atomic)
            XCTAssertThrowsError(try JSONDiskPersistence(url: url).load())
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            try original.write(to: url, options: .atomic)
        }
        XCTAssertEqual(try JSONDiskPersistence(url: url).load(), store.state)
    }

    func testV2MissingOriginsCannotSilentlyBecomeLegacyCards() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        _ = try GameStore(persistence: JSONDiskPersistence(url: url))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var cards = try XCTUnwrap(object["cards"] as? [[String: Any]])
        for index in cards.indices { cards[index].removeValue(forKey: "origin") }
        object["cards"] = cards
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: url, options: .atomic)
        XCTAssertThrowsError(try GameStore(persistence: JSONDiskPersistence(url: url)))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("v1.backup").path))
    }

    func testStarterOriginsMustCoverExactlyNineUniquePositions() throws {
        var state = try GameStore(persistence: MemoryPersistence()).state
        let last = try XCTUnwrap(state.cards.last)
        state.cards.removeLast()
        state.lineup.removeValue(forKey: last.position.rawValue)
        state.cards.append(PlayerCard(catalogID: "replacement", defaultName: "같은 포지션", tier: .rookie,
                                     position: .pitcher, origin: .starter))
        XCTAssertThrowsError(try state.validate())
    }

    private func makeDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func legacyData(cards: [PlayerCard], lineup: [String: UUID], earned: Int64 = 100_000) throws -> Data {
        var encodedCards = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cards)) as? [[String: Any]])
        for index in encodedCards.indices { encodedCards[index].removeValue(forKey: "origin") }
        let spent: Int64 = cards.reduce(0) { $0 + ($1.tier == .rookie ? 10 : $1.tier == .allStar ? 30 : 100) }
        let object: [String: Any] = ["schemaVersion": 1, "totalTokens": Int64(100_000_000),
            "earnedCurrency": earned, "spentCurrency": spent, "cards": encodedCards,
            "lineup": lineup.mapValues(\.uuidString), "sourceTotals": ["codex:old": Int64(100_000_000)],
            "lastImport": 123.5, "importFolders": ["codex": "/tmp/codex"]]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
