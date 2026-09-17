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
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("broken save".utf8)
        try bytes.write(to: url)
        let disk = JSONDiskPersistence(url: url)
        XCTAssertThrowsError(try GameStore(persistence: disk)) { XCTAssertEqual($0 as? GameError, .corruptSave) }
        XCTAssertThrowsError(try disk.save(GameState()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testUnknownSchemaIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
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
}
