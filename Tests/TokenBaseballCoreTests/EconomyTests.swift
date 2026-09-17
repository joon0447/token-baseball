import Foundation
import XCTest
@testable import TokenBaseballCore

final class EconomyTests: XCTestCase {
    func testDrawThresholdUsesRawTokensAndCarriesProgressAcrossRestart() throws {
        XCTAssertEqual(DrawPolicy.tokensPerDraw, 50_000_000)
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 49_999_999)])
        XCTAssertEqual(store.state.availableDraws, 0)
        XCTAssertThrowsError(try store.openDraw()) { XCTAssertEqual($0 as? GameError, .noDrawsAvailable) }
        XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:s", totalTokens: 50_000_000)]), 1)
        XCTAssertEqual(store.state.availableDraws, 1)
        let id = try store.openDraw()
        XCTAssertEqual(store.state.cards.count, 10)
        XCTAssertNotNil(store.state.cards.first { $0.id == id })
        XCTAssertEqual(store.state.totalTokens, 50_000_000)
        XCTAssertEqual(store.state.openedDraws, 1)
        XCTAssertEqual(store.state.availableDraws, 0)
        let restarted = try GameStore(persistence: disk)
        XCTAssertEqual(try restarted.importUsage([.init(sourceID: "codex:s", totalTokens: 50_000_000)]), 0)
        XCTAssertEqual(restarted.state.availableDraws, 0)
        _ = try restarted.importUsage([.init(sourceID: "claude:s", totalTokens: 50_000_000)])
        XCTAssertEqual(restarted.state.availableDraws, 1)
    }

    func testDrawGradeBoundariesAndPositionAreDeterministicWithInjectedSource() throws {
        for (roll, tier) in [(0, CardTier.rookie), (74, .rookie), (75, .allStar), (94, .allStar), (95, .legend), (99, .legend)] {
            let store = try GameStore(persistence: MemoryPersistence(), randomIndex: { bound in bound == 100 ? roll : bound - 1 })
            _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 100_000_000)])
            let firstID = try store.openDraw()
            let secondID = try store.openDraw()
            let first = try XCTUnwrap(store.state.cards.first { $0.id == firstID })
            let second = try XCTUnwrap(store.state.cards.first { $0.id == secondID })
            XCTAssertEqual(first.tier, tier)
            XCTAssertEqual(first.position, .rightField)
            XCTAssertEqual(first.name, second.name)
            XCTAssertNotEqual(first.id, second.id)
            XCTAssertEqual(store.state.lineup.count, 9)
        }
    }

    func testDailyUsageReplacesAttributionWithoutInventingTodaysHistory() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 10_000)])
        XCTAssertEqual(store.state.tokens(on: "2026-09-17"), 0)
        XCTAssertEqual(try store.importUsage([.init(sourceID: "codex:s", totalTokens: 10_000,
            dailyTokens: ["2026-09-16": 4_000, "2026-09-17": 6_000])]), 0)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 9_000,
            dailyTokens: ["2026-09-16": 3_000, "2026-09-17": 6_000]),
            .init(sourceID: "claude:s", totalTokens: 2_000, dailyTokens: ["2026-09-17": 2_000])])
        XCTAssertEqual(store.state.totalTokens, 12_000)
        XCTAssertEqual(store.state.tokens(on: "2026-09-16"), 3_000)
        XCTAssertEqual(store.state.tokens(on: "2026-09-17"), 8_000)
        XCTAssertEqual(try GameStore(persistence: disk).state.sourceDailyTotals, store.state.sourceDailyTotals)
    }

    func testInvalidDailyBatchesAndOverflowAreAtomic() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        let original = store.state
        let invalid: [UsageSnapshot] = [
            .init(sourceID: "s", totalTokens: -1),
            .init(sourceID: " ", totalTokens: 1),
            .init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-09-17": -1]),
            .init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-02-30": 1]),
            .init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-09-17": 11]),
            .init(sourceID: "s", totalTokens: Int64.max, dailyTokens: ["2026-09-16": Int64.max, "2026-09-17": 1])
        ]
        for snapshot in invalid {
            XCTAssertThrowsError(try store.importUsage([.init(sourceID: "good", totalTokens: 1), snapshot]))
            XCTAssertEqual(store.state, original)
        }
        _ = try store.importUsage([.init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-09-16": 10])])
        XCTAssertEqual(try store.importUsage([.init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-09-17": 10])]), 0)
        XCTAssertEqual(store.state.tokens(on: "2026-09-16"), 0)
        XCTAssertEqual(store.state.tokens(on: "2026-09-17"), 10)
        let before = store.state
        XCTAssertThrowsError(try store.importUsage([
            .init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-09-16": 10]),
            .init(sourceID: "s", totalTokens: 10, dailyTokens: ["2026-09-17": 10])]))
        XCTAssertEqual(store.state, before)
        _ = try store.importUsage([.init(sourceID: "s", totalTokens: Int64.max)])
        XCTAssertEqual(store.state.tokens(on: "2026-09-17"), 0)
        let maximum = store.state
        XCTAssertThrowsError(try store.importUsage([.init(sourceID: "another", totalTokens: 1)])) {
            XCTAssertEqual($0 as? GameError, .arithmeticOverflow)
        }
        XCTAssertEqual(store.state, maximum)
    }

    func testSaveFailureDoesNotCountUsageOrConsumeDraw() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        let fresh = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.importUsage([.init(sourceID: "s", totalTokens: 50_000_000)]))
        XCTAssertEqual(store.state, fresh)
        disk.shouldFail = false
        _ = try store.importUsage([.init(sourceID: "s", totalTokens: 50_000_000)])
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.openDraw())
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(disk.snapshot, before)
    }
}
