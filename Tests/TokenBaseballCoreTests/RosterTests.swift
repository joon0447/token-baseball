import Foundation
import XCTest
@testable import TokenBaseballCore

final class RosterTests: XCTestCase {
    func testAssignmentPreventsReuseAndRemovalKeepsOwnedCard() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 30_000)])
        let first = try store.purchase(offerID: Catalog.offers[0].id)
        let second = try store.purchase(offerID: Catalog.offers[1].id)
        try store.assign(cardID: first, to: .pitcher)
        try store.assign(cardID: first, to: .pitcher)
        XCTAssertThrowsError(try store.assign(cardID: first, to: .catcher)) {
            XCTAssertEqual($0 as? GameError, .cardAlreadyAssigned)
        }
        try store.assign(cardID: second, to: .pitcher)
        XCTAssertEqual(store.state.lineup[FieldPosition.pitcher.rawValue], second)
        XCTAssertEqual(store.state.cards.count, 2)
        try store.remove(from: .pitcher)
        XCTAssertTrue(store.state.lineup.isEmpty)
        XCTAssertEqual(store.state.cards.count, 2)
        XCTAssertEqual(store.state.balance, 10)
        try store.assign(cardID: first, to: .rightField)
        XCTAssertEqual(try GameStore(persistence: disk).state.lineup[FieldPosition.rightField.rawValue], first)
        XCTAssertThrowsError(try store.assign(cardID: UUID(), to: .pitcher)) {
            XCTAssertEqual($0 as? GameError, .cardNotFound)
        }
    }

    func testFailedSaveKeepsLineupUnchanged() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 10_000)])
        let cardID = try store.purchase(offerID: Catalog.offers[0].id)
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.assign(cardID: cardID, to: .pitcher))
        XCTAssertEqual(store.state, before)
    }
}
