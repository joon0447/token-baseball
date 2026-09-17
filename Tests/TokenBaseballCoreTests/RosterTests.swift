import Foundation
import XCTest
@testable import TokenBaseballCore

final class RosterTests: XCTestCase {
    func testPositionIsLockedAndReplacementRetainsInventory() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk, randomIndex: { _ in 0 })
        let starter = try XCTUnwrap(store.state.cards.first { $0.position == .pitcher })
        XCTAssertThrowsError(try store.assign(cardID: starter.id, to: .catcher)) {
            XCTAssertEqual($0 as? GameError, .positionMismatch)
        }
        _ = try store.importUsage([.init(sourceID: "s", totalTokens: 50_000_000)])
        let drawn = try store.openDraw()
        try store.assign(cardID: drawn, to: .pitcher)
        XCTAssertEqual(store.state.lineup["pitcher"], drawn)
        XCTAssertTrue(store.state.cards.contains { $0.id == starter.id })
        XCTAssertEqual(store.state.cards.count, 10)
        try store.assign(cardID: starter.id, to: .pitcher)
        XCTAssertTrue(store.state.cards.contains { $0.id == drawn })
        try store.remove(from: .pitcher)
        XCTAssertNil(store.state.lineup["pitcher"])
        XCTAssertEqual(store.state.cards.count, 10)
        try store.assign(cardID: starter.id, to: .pitcher)
        XCTAssertEqual(try GameStore(persistence: disk).state.lineup["pitcher"], starter.id)
        XCTAssertThrowsError(try store.assign(cardID: UUID(), to: .pitcher)) {
            XCTAssertEqual($0 as? GameError, .cardNotFound)
        }
    }

    func testFailedSaveKeepsLineupUnchanged() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.remove(from: .pitcher))
        XCTAssertEqual(store.state, before)
    }
}
