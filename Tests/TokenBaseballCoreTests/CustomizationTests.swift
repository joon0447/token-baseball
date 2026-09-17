import Foundation
import XCTest
@testable import TokenBaseballCore

final class CustomizationTests: XCTestCase {
    func testNamesAreTrimmedValidatedAndPersisted() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        let cardID = store.state.cards[0].id
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

    func testCustomizationResetPreservesIdentityPositionAndLineup() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        let original = store.state.cards[0]
        try store.rename(cardID: original.id, name: "내 선수")
        try store.setPhoto(cardID: original.id, data: Data([1, 2, 3]))
        XCTAssertEqual(try GameStore(persistence: disk).state.cards[0].photoData, Data([1, 2, 3]))
        try store.resetCustomization(cardID: original.id)
        XCTAssertEqual(store.state.cards[0], original)
        XCTAssertEqual(store.state.lineup[original.position.rawValue], original.id)
    }

    func testFailedCustomizationSaveLeavesCardUnchanged() throws {
        let disk = MemoryPersistence()
        let store = try GameStore(persistence: disk)
        let cardID = store.state.cards[0].id
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
