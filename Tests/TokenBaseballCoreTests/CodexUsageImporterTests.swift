import Foundation
import XCTest
@testable import TokenBaseballCore

final class CodexUsageImporterTests: XCTestCase {
    @MainActor
    func testCancelledTaskStopsBeforeReadingFolder() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CodexUsageImporter().read(folder: URL(fileURLWithPath: "/not-read-when-cancelled"))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled import should throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private let importer = CodexUsageImporter()

    func testDailyGrowthUsesTimestampOrderAcrossLocalMidnight() throws {
        try withFolder { folder in
            try write([metadata("a"),
                       tokens("170", timestamp: "2026-09-17T00:00:00.123Z"),
                       tokens("100", timestamp: "2026-09-16T14:59:00Z"),
                       tokens("150", timestamp: "2026-09-16T15:01:00Z"),
                       tokens("140", timestamp: "2026-09-17T00:01:00Z")], to: "session.jsonl", in: folder)
            let korea = CodexUsageImporter(calendar: calendar("Asia/Seoul"))
            XCTAssertEqual(try korea.read(folder: folder), [
                UsageSnapshot(sourceID: "codex:a", totalTokens: 170,
                              dailyTokens: ["2026-09-16": 100, "2026-09-17": 70])
            ])
            let utc = CodexUsageImporter(calendar: calendar("UTC"))
            XCTAssertEqual(try utc.read(folder: folder).first?.dailyTokens, ["2026-09-16": 150, "2026-09-17": 20])
        }
    }

    func testHistoricAndCopiedEventsDoNotBecomeUsageOnImportDay() throws {
        try withFolder { folder in
            let old = [metadata("history"), tokens("100", timestamp: "2020-02-01T23:00:00Z"),
                       tokens("160", timestamp: "2020-02-02T01:00:00Z")]
            try write(old, to: "sessions/original.jsonl", in: folder)
            try write(old + [tokens("160", timestamp: "2020-02-02T04:00:00Z")], to: "archived_sessions/copy.jsonl", in: folder)
            let reader = CodexUsageImporter(calendar: calendar("UTC"))
            let expected = [UsageSnapshot(sourceID: "codex:history", totalTokens: 160,
                                          dailyTokens: ["2020-02-01": 100, "2020-02-02": 60])]
            XCTAssertEqual(try reader.read(folder: folder), expected)
            XCTAssertEqual(try reader.read(folder: folder), expected)
        }
    }

    func testMissingAndInvalidTimestampsRemainAnUndatedBaseline() throws {
        try withFolder { folder in
            try write([metadata("a"), tokens("100"), tokens("120", timestamp: "not-a-timestamp"),
                       tokens("170", timestamp: "2026-09-17T01:00:00Z")], to: "session.jsonl", in: folder)
            let reader = CodexUsageImporter(calendar: calendar("UTC"))
            XCTAssertEqual(try reader.read(folder: folder), [
                UsageSnapshot(sourceID: "codex:a", totalTokens: 170, dailyTokens: ["2026-09-17": 50])
            ])
            try write([metadata("a"), tokens("200")], to: "session.jsonl", in: folder)
            XCTAssertEqual(try reader.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 200)])
        }
    }

    func testUnchangedFilesUseMetadataCacheAndEditsInvalidateIt() throws {
        try withFolder { folder in
            let reader = CodexUsageImporter(calendar: calendar("UTC"))
            try write([metadata("a"), tokens("100", timestamp: "2026-09-17T01:00:00Z")], to: "session.jsonl", in: folder)
            let file = folder.appendingPathComponent("session.jsonl")
            let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]!
            XCTAssertEqual(try reader.read(folder: folder).first?.totalTokens, 100)
            XCTAssertEqual(reader.parsedFileCount, 1)
            XCTAssertEqual(try reader.read(folder: folder).first?.totalTokens, 100)
            XCTAssertEqual(reader.parsedFileCount, 1)
            // Same size and restored mtime still invalidate via inode/ctime fingerprinting.
            try write([metadata("a"), tokens("200", timestamp: "2026-09-17T01:00:00Z")], to: "session.jsonl", in: folder)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
            XCTAssertEqual(try reader.read(folder: folder).first?.totalTokens, 200)
            XCTAssertEqual(reader.parsedFileCount, 2)
            try write([metadata("a"), tokens("200", timestamp: "2026-09-17T01:00:00Z"),
                       tokens("250", timestamp: "2026-09-17T02:00:00Z")], to: "session.jsonl", in: folder)
            XCTAssertEqual(try reader.read(folder: folder).first?.dailyTokens, ["2026-09-17": 250])
            XCTAssertEqual(reader.parsedFileCount, 3)
            try FileManager.default.removeItem(at: file)
            XCTAssertEqual(try reader.read(folder: folder), [])
        }
    }

    @MainActor
    func testSharedImporterCanReadConcurrently() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try write([metadata("a"), tokens("100")], to: "session.jsonl", in: folder)
        let reader = CodexUsageImporter()
        let results = try await withThrowingTaskGroup(of: [UsageSnapshot].self) { group in
            for _ in 0..<4 { group.addTask { try reader.read(folder: folder) } }
            var results: [[UsageSnapshot]] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy { $0 == [UsageSnapshot(sourceID: "codex:a", totalTokens: 100)] })
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    func testDesktopSessionIDRemainsStableAcrossResumedMetadataAndCopiedFiles() throws {
        try withFolder { folder in
            let first = #"{"type":"session_meta","payload":{"id":"metadata-one","session_id":"stable-session"}}"#
            let resumed = #"{"type":"session_meta","payload":{"id":"metadata-two","session_id":"stable-session"}}"#
            try write([first, tokens("100"), resumed, tokens("150")], to: "sessions/one.jsonl", in: folder)
            try write([resumed, tokens("170")], to: "archived_sessions/copy.jsonl", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:stable-session", totalTokens: 170)])
        }
    }

    func testPresentButInvalidDesktopSessionIDDoesNotFallBackToMetadataID() throws {
        for value in ["null", "123", "false", "\"\"", "\"two words\""] {
            try withFolder { folder in
                let record = #"{"type":"session_meta","payload":{"id":"valid-metadata","session_id":"# + value + "}}"
                try write([record, tokens("100")], to: "session.jsonl", in: folder)
                XCTAssertThrowsError(try importer.read(folder: folder)) { error in
                    XCTAssertEqual(error as? CodexUsageImportError, .invalidSessionMetadata(line: 1))
                }
            }
        }
    }

    func testConflictingDesktopSessionIDsStillFail() throws {
        try withFolder { folder in
            let first = #"{"type":"session_meta","payload":{"id":"metadata","session_id":"session-a"}}"#
            let different = #"{"type":"session_meta","payload":{"id":"metadata","session_id":"session-b"}}"#
            try write([first, tokens("100"), different], to: "session.jsonl", in: folder)
            XCTAssertThrowsError(try importer.read(folder: folder)) { error in
                XCTAssertEqual(error as? CodexUsageImportError, .invalidSessionMetadata(line: 3))
            }
        }
    }

    func testCumulativeMaximumAndArchiveCopiesAreDeduplicated() throws {
        try withFolder { folder in
            try write([metadata("a"), tokens("100"), tokens("220"), tokens("180")],
                      to: "sessions/2026/one.jsonl", in: folder)
            try write([metadata("a"), tokens("240")], to: "archived_sessions/copy.jsonl", in: folder)
            try write([metadata("b"), tokens("70")], to: "sessions/two.jsonl", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [
                UsageSnapshot(sourceID: "codex:a", totalTokens: 240),
                UsageSnapshot(sourceID: "codex:b", totalTokens: 70)
            ])
        }
    }

    func testRootIgnoresUnrelatedHistoryAndNonJSONLFiles() throws {
        try withFolder { folder in
            try write([metadata("a"), tokens("50")], to: "sessions/one.jsonl", in: folder)
            try write(["invalid unrelated content"], to: "history.jsonl", in: folder)
            try write(["invalid unrelated content"], to: "sessions/notes.txt", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 50)])
        }
    }

    func testEmptyFoldersReturnNoSnapshotsAndMissingFolderThrows() throws {
        try withFolder { folder in
            XCTAssertEqual(try importer.read(folder: folder), [])
            XCTAssertThrowsError(try importer.read(folder: folder.appendingPathComponent("missing"))) { error in
                XCTAssertEqual(error as? CodexUsageImportError, .invalidFolder)
            }
            let home = folder.appendingPathComponent(".codex")
            try write(["unrelated history"], to: "history.jsonl", in: home)
            XCTAssertEqual(try importer.read(folder: home), [])
        }
    }

    func testUserSelectedNestedSessionFolderIsSupported() throws {
        try withFolder { folder in
            try write([metadata("nested"), tokens("80")], to: "2026/09/session.jsonl", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:nested", totalTokens: 80)])
        }
    }

    func testInvalidTokenValuesFailTheWholeImport() throws {
        for value in ["-1", "true", "false", "1.0", "1.5", "1e3", "9007199254740993.1",
                      "9223372036854775808", "\"100\"", "null", "{}", "[]"] {
            try withFolder { folder in
                try write([metadata("valid"), tokens("20")], to: "a.jsonl", in: folder)
                try write([metadata("invalid"), tokens(value)], to: "b.jsonl", in: folder)
                XCTAssertThrowsError(try importer.read(folder: folder), "Expected failure for \(value)") { error in
                    XCTAssertEqual(error as? CodexUsageImportError, .invalidTokenCount(line: 2))
                }
            }
        }
    }

    func testZeroAndInt64MaximumRemainExact() throws {
        try withFolder { folder in
            try write([metadata("zero"), tokens("0")], to: "zero.jsonl", in: folder)
            try write([metadata("max"), tokens("9223372036854775807")], to: "max.jsonl", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [
                UsageSnapshot(sourceID: "codex:max", totalTokens: Int64.max),
                UsageSnapshot(sourceID: "codex:zero", totalTokens: 0)
            ])
        }
    }

    func testMissingUsageFieldsFailAndNullInfoIsIgnored() throws {
        let invalidRecords = [
            #"{"type":"event_msg","payload":{"type":"token_count"}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{}}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{}}}}"#
        ]
        for record in invalidRecords {
            try withFolder { folder in
                try write([metadata("a"), record], to: "one.jsonl", in: folder)
                XCTAssertThrowsError(try importer.read(folder: folder))
            }
        }
        try withFolder { folder in
            try write([metadata("a"), #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{}}}"#],
                      to: "one.jsonl", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [])
        }
    }

    func testSessionMetadataIsRequiredAndFilenameNeverActsAsIdentity() throws {
        try withFolder { folder in
            try write([tokens("100")], to: "rollout-pretend-session-id.jsonl", in: folder)
            XCTAssertThrowsError(try importer.read(folder: folder)) { error in
                XCTAssertEqual(error as? CodexUsageImportError, .missingSessionMetadata)
            }
        }
    }

    func testConflictingOrInvalidSessionMetadataFails() throws {
        for record in [metadata("b"), metadata(""), metadata("bad id"), #"{"type":"session_meta","payload":{"id":false}}"#] {
            try withFolder { folder in
                try write([metadata("a"), record, tokens("100")], to: "one.jsonl", in: folder)
                XCTAssertThrowsError(try importer.read(folder: folder)) { error in
                    XCTAssertEqual(error as? CodexUsageImportError, .invalidSessionMetadata(line: 2))
                }
            }
        }
    }

    func testIncompleteFinalLineIsIgnoredOnlyWithoutNewline() throws {
        try withFolder { folder in
            let partial = #"{"type":"event_msg","payload":{"type":"token_count","info": {"#
            try write([metadata("a"), tokens("75"), partial], to: "one.jsonl", in: folder, finalNewline: false)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 75)])
            try write([metadata("a"), tokens("75"), partial], to: "one.jsonl", in: folder)
            XCTAssertThrowsError(try importer.read(folder: folder)) { error in
                XCTAssertEqual(error as? CodexUsageImportError, .malformedRecord(line: 3))
            }
        }
    }

    func testValidFinalLineWithoutNewlineIsCountedAndInvalidValueStillFails() throws {
        try withFolder { folder in
            try write([metadata("a"), tokens("80")], to: "one.jsonl", in: folder, finalNewline: false)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 80)])
            try write([metadata("a"), tokens("false")], to: "one.jsonl", in: folder, finalNewline: false)
            XCTAssertThrowsError(try importer.read(folder: folder))
        }
    }

    func testIgnoresConversationRecordsAndOtherTokenFields() throws {
        try withFolder { folder in
            let unrelated = #"{"type":"response_item","payload":{"type":"message","content":[{"text":"synthetic fixture"}]}}"#
            let usage = #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":500},"total_token_usage":{"total_tokens":90,"input_tokens":60,"output_tokens":30,"cached_input_tokens":40}}}}"#
            try write([metadata("a"), unrelated, usage], to: "one.jsonl", in: folder)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 90)])
        }
    }

    func testSymbolicLinkFilesAreNotFollowed() throws {
        try withFolder { folder in
            try write([metadata("a"), tokens("50")], to: "one.jsonl", in: folder)
            let external = folder.appendingPathComponent("outside.txt")
            try Data("invalid JSON".utf8).write(to: external)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked.jsonl"),
                                                      withDestinationURL: external)
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 50)])
        }
    }

    func testStreamingAcrossChunkBoundariesAndCRLF() throws {
        try withFolder { folder in
            let longIgnoredRecord = #"{"type":"response_item","payload":""# + String(repeating: "x", count: 70_000) + #""}"#
            let contents = [metadata("a"), longIgnoredRecord, tokens("120")].joined(separator: "\r\n") + "\r\n"
            try Data(contents.utf8).write(to: folder.appendingPathComponent("one.jsonl"))
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "codex:a", totalTokens: 120)])
        }
    }

    private func metadata(_ id: String) -> String {
        #"{"type":"session_meta","payload":{"id":""# + id + #""}}"#
    }

    private func tokens(_ value: String, timestamp: String? = nil) -> String {
        let record = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":"# + value + #"}}}}"#
        guard let timestamp else { return record }
        return "{\"timestamp\":\"\(timestamp)\"," + String(record.dropFirst())
    }

    private func write(_ lines: [String], to path: String, in folder: URL, finalNewline: Bool = true) throws {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + (finalNewline ? "\n" : "")).utf8).write(to: file)
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CodexUsageImporterTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }
}
