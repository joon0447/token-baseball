import Foundation
import XCTest
@testable import TokenBaseballCore

final class TokenDisplayTests: XCTestCase {
    func testCompactUnitsDoNotRoundUpToAnUnearnedThreshold() {
        let examples: [(Int64, String)] = [(0, "0"), (999, "999"), (1_000, "1K"), (1_250, "1.2K"),
            (999_999, "999.9K"), (1_000_000, "1M"), (12_345_678, "12.3M"), (3_734_764_842, "3.7B")]
        for (number, expected) in examples { XCTAssertEqual(TokenDisplay.short(number), expected) }
    }

    func testDayKeyUsesMacCalendarTimezone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let utc = ISO8601DateFormatter().date(from: "2026-09-17T15:00:00Z")!
        XCTAssertEqual(TokenDisplay.dayKey(utc, calendar: calendar), "2026-09-18")
    }

    func testNonGregorianPreferencesKeepGregorianKeysAndLocalMidnight() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T15:00:00Z"))
        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3_600))
            XCTAssertNotEqual(calendar.component(.year, from: instant), 2026)
            XCTAssertEqual(TokenDisplay.dayKey(instant, calendar: calendar), "2026-09-18")
            calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -7 * 3_600))
            XCTAssertEqual(TokenDisplay.dayKey(instant, calendar: calendar), "2026-09-17")
        }
    }

}
