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
    func testNewStoreStartsWithoutCardsOrCurrency() throws {
        let store = try GameStore(persistence: MemoryPersistence())
        XCTAssertEqual(store.state, GameState())
        XCTAssertEqual(Catalog.offers.count, 27)
        XCTAssertEqual(Set(Catalog.offers.map(\.id)).count, 27)
        for tier in CardTier.allCases {
            XCTAssertEqual(Catalog.offers.filter { $0.tier == tier }.count, 9)
        }
    }

    func testFolderSettingsPersistAndRollbackOnFailure() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        try store.setImportFolder("/tmp/codex", for: "codex")
        try store.setImportFolder("/tmp/claude", for: "claude")
        XCTAssertEqual(try GameStore(persistence: disk).state.importFolders,
                       ["codex": "/tmp/codex", "claude": "/tmp/claude"])
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.setImportFolder("/tmp/new", for: "codex"))
        XCTAssertEqual(store.state, before)
        XCTAssertThrowsError(try store.setImportFolder("relative/path", for: "claude"))
        XCTAssertThrowsError(try store.setImportFolder("/tmp/path", for: "unknown"))
    }

    func testJSONRoundTripPreservesCardsPhotosAndLineup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JSONDiskPersistence(url: directory.appendingPathComponent("state.json"))
        XCTAssertNil(try disk.load())
        let offer = try XCTUnwrap(Catalog.offers.first)
        let card = PlayerCard(catalogID: offer.id, defaultName: offer.name, customName: "내 에이스",
                              tier: offer.tier, position: offer.position, photoData: Data([1, 2, 3]))
        let original = GameState(totalTokens: 15_500, earnedCurrency: 15, spentCurrency: 10,
                                 cards: [card], lineup: [FieldPosition.pitcher.rawValue: card.id],
                                 sourceTotals: ["codex:test": 15_500], lastImport: Date(timeIntervalSince1970: 123.5),
                                 importFolders: ["codex": "/tmp/codex"])
        try disk.save(original)
        XCTAssertEqual(try disk.load(), original)
        XCTAssertEqual(try GameStore(persistence: disk).state.balance, 5)
    }

    func testCorruptFileIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("lock"))
        }
        let bytes = Data("broken save".utf8)
        try bytes.write(to: url)
        let disk = JSONDiskPersistence(url: url)
        XCTAssertThrowsError(try GameStore(persistence: disk)) { XCTAssertEqual($0 as? GameError, .corruptSave) }
        XCTAssertThrowsError(try disk.save(GameState()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testUnknownSchemaIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("lock"))
        }
        let bytes = Data("{\"schemaVersion\":99}".utf8)
        try bytes.write(to: url)
        let disk = JSONDiskPersistence(url: url)
        XCTAssertThrowsError(try disk.load()) { XCTAssertEqual($0 as? GameError, .unsupportedSchema(99)) }
        XCTAssertThrowsError(try disk.save(GameState()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testInvalidLedgerAndDanglingLineupAreRejectedOnLoad() throws {
        var invalid = GameState(totalTokens: -1)
        XCTAssertThrowsError(try GameStore(persistence: MemoryPersistence(snapshot: invalid)))
        invalid = GameState(totalTokens: 2_000, earnedCurrency: 999, sourceTotals: ["codex:s": 2_000])
        XCTAssertThrowsError(try invalid.validate())
        invalid = GameState(totalTokens: 2_000, earnedCurrency: 2, spentCurrency: 3, sourceTotals: ["codex:s": 2_000])
        XCTAssertThrowsError(try invalid.validate())
        invalid = GameState(lineup: [FieldPosition.pitcher.rawValue: UUID()])
        XCTAssertThrowsError(try invalid.validate())
        invalid = GameState(sourceTotals: ["codex:s": 1])
        XCTAssertThrowsError(try invalid.validate())
    }

    func testDuplicateCardsAndLineupAreRejected() throws {
        let offer = try XCTUnwrap(Catalog.offers.first)
        let card = PlayerCard(catalogID: offer.id, defaultName: offer.name, tier: offer.tier, position: offer.position)
        var state = GameState(totalTokens: 20_000, earnedCurrency: 20, spentCurrency: 20,
                              cards: [card, card], sourceTotals: ["codex:s": 20_000])
        XCTAssertThrowsError(try state.validate())
        state.cards = [card]
        state.spentCurrency = 10
        state.lineup = [FieldPosition.pitcher.rawValue: card.id, FieldPosition.catcher.rawValue: card.id]
        XCTAssertThrowsError(try state.validate())
    }

    func testFractionalHugeStoredTokensAreRejectedWithoutChangingFile() throws {
        try withDisk { disk in
            let tokens: Int64 = 9_007_199_254_740_993
            let state = GameState(totalTokens: tokens, earnedCurrency: tokens / GameState.tokensPerCurrency,
                                  sourceTotals: ["codex:synthetic": tokens])
            let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
                .replacingOccurrences(of: String(tokens), with: "9007199254740993.1")
            let bytes = Data(json.utf8)
            try bytes.write(to: disk.url)
            XCTAssertThrowsError(try disk.load()) { XCTAssertEqual($0 as? GameError, .corruptSave) }
            XCTAssertThrowsError(try disk.save(state)) { XCTAssertEqual($0 as? GameError, .corruptSave) }
            XCTAssertEqual(try Data(contentsOf: disk.url), bytes)
        }
    }

    func testStoredLedgerNumbersMustBeNonnegativeIntegerLiterals() throws {
        for field in ["schemaVersion", "totalTokens", "earnedCurrency", "spentCurrency", "sourceTotal"] {
            for value in ["true", "false", "1.0", "1e3", "-1", "9223372036854775808", "\"1\"", "null"] {
                try withDisk { disk in
                    let fields = [
                        "schemaVersion": field == "schemaVersion" ? value : "1",
                        "totalTokens": field == "totalTokens" ? value : "0",
                        "earnedCurrency": field == "earnedCurrency" ? value : "0",
                        "spentCurrency": field == "spentCurrency" ? value : "0"
                    ]
                    let ledger = fields.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
                    let total = field == "sourceTotal" ? value : "0"
                    let bytes = Data(("{" + ledger + ",\"sourceTotals\":{\"codex:test\":" + total
                                      + "},\"cards\":[],\"lineup\":{},\"importFolders\":{}}").utf8)
                    try bytes.write(to: disk.url)
                    XCTAssertThrowsError(try disk.load(), "Accepted \(field)=\(value)") {
                        XCTAssertEqual($0 as? GameError, .corruptSave)
                    }
                    XCTAssertEqual(try Data(contentsOf: disk.url), bytes)
                }
            }
        }
    }

    func testDirectInitialSaveAndInt64MaximumRoundTrip() throws {
        try withDisk { disk in
            let initial = GameState(totalTokens: Int64.max, earnedCurrency: Int64.max / GameState.tokensPerCurrency,
                                    sourceTotals: ["codex:max": Int64.max])
            // Saving into an absent file remains supported without a preceding load.
            try disk.save(initial)
            XCTAssertEqual(try disk.load(), initial)
            let unopened = JSONDiskPersistence(url: disk.url)
            XCTAssertThrowsError(try unopened.save(GameState())) { XCTAssertEqual($0 as? GameError, .staleSave) }
            XCTAssertEqual(try disk.load(), initial)
        }
    }

    func testStaleUsageWriterIsRejectedAndCanReloadThroughNewInstance() throws {
        try withDisk { disk in
            let first = try GameStore(persistence: disk)
            let second = try GameStore(persistence: JSONDiskPersistence(url: disk.url))
            try first.importUsage([.init(sourceID: "codex:first", totalTokens: 50_000)])
            let bytes = try Data(contentsOf: disk.url)
            // A failed conflict check must not advance the stale writer's baseline.
            for _ in 0..<2 {
                XCTAssertThrowsError(try second.importUsage([.init(sourceID: "claude:second", totalTokens: 30_000)])) {
                    XCTAssertEqual($0 as? GameError, .staleSave)
                }
                XCTAssertEqual(second.state, GameState())
                XCTAssertEqual(try Data(contentsOf: disk.url), bytes)
            }
            let reloaded = try GameStore(persistence: JSONDiskPersistence(url: disk.url))
            XCTAssertEqual(reloaded.state, first.state)
            try reloaded.importUsage([.init(sourceID: "claude:second", totalTokens: 30_000)])
            XCTAssertEqual(reloaded.state.totalTokens, 80_000)
            XCTAssertEqual(try JSONDiskPersistence(url: disk.url).load(), reloaded.state)
        }
    }

    func testStalePurchaseCannotLoseAnotherPurchaseOrDebitFunds() throws {
        try withDisk { disk in
            try disk.save(GameState(totalTokens: 50_000, earnedCurrency: 50, sourceTotals: ["codex:test": 50_000]))
            let first = try GameStore(persistence: disk)
            let second = try GameStore(persistence: JSONDiskPersistence(url: disk.url))
            let secondBefore = second.state
            try first.purchase(offerID: Catalog.offers[0].id)
            let bytes = try Data(contentsOf: disk.url)
            XCTAssertThrowsError(try second.purchase(offerID: Catalog.offers[1].id)) {
                XCTAssertEqual($0 as? GameError, .staleSave)
            }
            XCTAssertEqual(second.state, secondBefore)
            XCTAssertEqual(try Data(contentsOf: disk.url), bytes)
            let reloaded = try GameStore(persistence: JSONDiskPersistence(url: disk.url))
            try reloaded.purchase(offerID: Catalog.offers[1].id)
            XCTAssertEqual(reloaded.state.cards.count, 2)
            XCTAssertEqual(reloaded.state.balance, 30)
        }
    }

    func testSemanticCorruptionAfterLoadPreservesFileAndExpectedSnapshot() throws {
        try withDisk { disk in
            let store = try GameStore(persistence: disk)
            try store.importUsage([.init(sourceID: "codex:test", totalTokens: 50_000)])
            let before = store.state
            let originalBytes = try Data(contentsOf: disk.url)
            var corrupt = before
            corrupt.earnedCurrency = 999
            let corruptBytes = try JSONEncoder().encode(corrupt)
            try corruptBytes.write(to: disk.url)
            XCTAssertThrowsError(try disk.load())
            XCTAssertThrowsError(try store.importUsage([.init(sourceID: "codex:test", totalTokens: 60_000)]))
            XCTAssertEqual(store.state, before)
            XCTAssertEqual(try Data(contentsOf: disk.url), corruptBytes)
            try originalBytes.write(to: disk.url)
            XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:test", totalTokens: 60_000)]), 10_000)
        }
    }

    func testActualDiskWriteFailureDoesNotAdvanceExpectedSnapshot() throws {
        try withDisk { disk in
            try disk.save(GameState())
            let store = try GameStore(persistence: disk)
            let directory = disk.url.deletingLastPathComponent()
            let originalBytes = try Data(contentsOf: disk.url)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
            XCTAssertThrowsError(try store.importUsage([.init(sourceID: "codex:test", totalTokens: 1_000)]))
            XCTAssertEqual(store.state, GameState())
            XCTAssertEqual(try Data(contentsOf: disk.url), originalBytes)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:test", totalTokens: 1_000)]), 1_000)
        }
    }

    func testConcurrentWritersSerializeComparisonAndAtomicSave() throws {
        try withDisk { disk in
            try disk.save(GameState())
            let url = disk.url
            let ready = DispatchGroup()
            let finished = DispatchGroup()
            let start = DispatchSemaphore(value: 0)
            let results = ConcurrentSaveResults()
            for index in 1...2 {
                ready.enter()
                finished.enter()
                DispatchQueue.global().async {
                    defer { finished.leave() }
                    let writer = JSONDiskPersistence(url: url)
                    do {
                        _ = try writer.load()
                    } catch {
                        results.record(error)
                        ready.leave()
                        return
                    }
                    ready.leave()
                    start.wait()
                    do {
                        let tokens = Int64(index) * 1_000
                        try writer.save(GameState(totalTokens: tokens, earnedCurrency: Int64(index),
                                                  sourceTotals: ["codex:writer-\(index)": tokens]))
                        results.record(nil)
                    } catch {
                        results.record(error)
                    }
                }
            }
            XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
            start.signal()
            start.signal()
            XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)
            let outcome = results.counts
            XCTAssertEqual(outcome.success, 1)
            XCTAssertEqual(outcome.stale, 1)
            XCTAssertEqual(outcome.other, 0)
            let saved = try XCTUnwrap(JSONDiskPersistence(url: url).load())
            XCTAssertTrue([Int64(1_000), 2_000].contains(saved.totalTokens))
        }
    }

    private func withDisk(_ body: (JSONDiskPersistence) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PersistenceTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(JSONDiskPersistence(url: directory.appendingPathComponent("state.json")))
    }
}

private final class ConcurrentSaveResults: @unchecked Sendable {
    private let lock = NSLock()
    private var success = 0
    private var stale = 0
    private var other = 0

    func record(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if error == nil { success += 1 }
        else if error as? GameError == .staleSave { stale += 1 }
        else { other += 1 }
    }

    var counts: (success: Int, stale: Int, other: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (success, stale, other)
    }
}
