import Foundation
import XCTest
@testable import TokenBaseballCore

final class CustomizationTests: XCTestCase {
    func testNamesAreTrimmedValidatedAndPersisted() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 10_000)])
        let cardID = try store.purchase(offerID: Catalog.offers[0].id)
        try store.rename(cardID: cardID, name: "  우리 에이스\n")
        XCTAssertEqual(store.state.cards[0].name, "우리 에이스")
        XCTAssertEqual(try GameStore(persistence: disk).state.cards[0].name, "우리 에이스")
        for name in ["", " \n ", String(repeating: "가", count: 31)] {
            XCTAssertThrowsError(try store.rename(cardID: cardID, name: name)) {
                XCTAssertEqual($0 as? GameError, .invalidName)
            }
        }
        try store.rename(cardID: cardID, name: String(repeating: "가", count: 30))
        XCTAssertEqual(store.state.cards[0].name.count, 30)
    }

    func testCustomizationResetPreservesCardAndLineup() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 10_000)])
        let cardID = try store.purchase(offerID: Catalog.offers[0].id)
        try store.assign(cardID: cardID, to: .pitcher)
        try store.rename(cardID: cardID, name: "내 선수")
        try store.setPhoto(cardID: cardID, data: Data([1, 2, 3]))
        XCTAssertEqual(try GameStore(persistence: disk).state.cards[0].photoData, Data([1, 2, 3]))
        try store.resetCustomization(cardID: cardID)
        XCTAssertEqual(store.state.cards[0].name, Catalog.offers[0].name)
        XCTAssertNil(store.state.cards[0].customName)
        XCTAssertNil(store.state.cards[0].photoData)
        XCTAssertEqual(store.state.lineup[FieldPosition.pitcher.rawValue], cardID)
        XCTAssertEqual(store.state.balance, 0)
    }

    func testFailedCustomizationSaveLeavesCardUnchanged() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        _ = try store.importUsage([.init(sourceID: "codex:s", totalTokens: 10_000)])
        let cardID = try store.purchase(offerID: Catalog.offers[0].id)
        let before = store.state
        disk.shouldFail = true
        XCTAssertThrowsError(try store.rename(cardID: cardID, name: "이름"))
        XCTAssertThrowsError(try store.setPhoto(cardID: cardID, data: Data([1])))
        XCTAssertEqual(store.state, before)
        XCTAssertThrowsError(try store.resetCustomization(cardID: UUID())) {
            XCTAssertEqual($0 as? GameError, .cardNotFound)
        }
    }
}
