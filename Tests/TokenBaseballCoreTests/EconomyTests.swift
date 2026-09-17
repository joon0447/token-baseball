import Foundation
import XCTest
@testable import TokenBaseballCore

final class EconomyTests: XCTestCase {
    func testImportCarriesRemainderAndIsIdempotentAcrossRestart() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:one", totalTokens: 500)]), 500)
        XCTAssertEqual(store.state.balance, 0)
        XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:one", totalTokens: 1_500)]), 1_000)
        XCTAssertEqual(store.state.balance, 1)
        let restarted = try GameStore(persistence: disk)
        XCTAssertEqual(try restarted.importUsage([.init(sourceID: "codex:one", totalTokens: 1_500)]), 0)
        XCTAssertEqual(try restarted.importUsage([.init(sourceID: "claude:one", totalTokens: 500)]), 500)
        XCTAssertEqual(restarted.state.totalTokens, 2_000)
        XCTAssertEqual(restarted.state.balance, 2)
    }

    func testSourceHighWaterDoesNotDecreaseAndDuplicatesUseMaximum() throws {
        let store = try GameStore(persistence: MemoryPersistence())
        XCTAssertEqual(try store.importUsage([
            .init(sourceID: "codex:s", totalTokens: 1_500),
            .init(sourceID: "codex:s", totalTokens: 1_000),
            .init(sourceID: "codex:s", totalTokens: 2_000)
        ]), 2_000)
        XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:s", totalTokens: 1)]), 0)
        XCTAssertEqual(store.state.sourceTotals["codex:s"], 2_000)
    }

    func testInvalidBatchAndOverflowLeaveEntireStateUnchanged() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        XCTAssertThrowsError(try store.importUsage([
            .init(sourceID: "codex:good", totalTokens: 1_000),
            .init(sourceID: "claude:bad", totalTokens: -1)
        ])) { XCTAssertEqual($0 as? GameError, .invalidUsage) }
        XCTAssertEqual(store.state, GameState())
        XCTAssertEqual(disk.saveCount, 0)
        XCTAssertThrowsError(try store.importUsage([.init(sourceID: "  ", totalTokens: 1)]))
        _ = try store.importUsage([.init(sourceID: "codex:max", totalTokens: Int64.max)])
        let before = store.state
        XCTAssertThrowsError(try store.importUsage([.init(sourceID: "claude:overflow", totalTokens: 1)])) {
            XCTAssertEqual($0 as? GameError, .arithmeticOverflow)
        }
        XCTAssertEqual(store.state, before)
    }

    func testFailedSaveDoesNotCreditTokensOrGrantCard() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        disk.shouldFail = true
        XCTAssertThrowsError(try store.importUsage([.init(sourceID: "codex:s", totalTokens: 50_000)]))
        XCTAssertEqual(store.state, GameState())
        disk.shouldFail = false
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 50_000)])
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.purchase(offerID: Catalog.offers[0].id))
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(disk.snapshot, before)
    }

    func testPurchaseRequiresFundsAndPreventsDuplicate() throws {
        let store = try GameStore(persistence: MemoryPersistence())
        let offer = Catalog.offers[0]
        XCTAssertThrowsError(try store.purchase(offerID: offer.id)) {
            XCTAssertEqual($0 as? GameError, .insufficientFunds(required: 10, available: 0))
        }
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 25_000)])
        let cardID = try store.purchase(offerID: offer.id)
        XCTAssertEqual(store.state.balance, 15)
        XCTAssertEqual(store.state.spentCurrency, 10)
        XCTAssertEqual(store.state.cards.first?.id, cardID)
        XCTAssertEqual(store.state.cards.first?.catalogID, offer.id)
        let before = store.state
        XCTAssertThrowsError(try store.purchase(offerID: offer.id)) { XCTAssertEqual($0 as? GameError, .alreadyOwned) }
        XCTAssertThrowsError(try store.purchase(offerID: "missing")) { XCTAssertEqual($0 as? GameError, .unknownOffer) }
        XCTAssertEqual(store.state, before)
    }
}
