import Foundation
import XCTest
@testable import TokenBaseballCore

final class ClaudeUsageImporterTests: XCTestCase {
    @MainActor
    func testCancelledTaskStopsBeforeReadingFolder() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ClaudeUsageImporter().read(folder: URL(fileURLWithPath: "/not-read-when-cancelled"))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled import should throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private let importer = ClaudeUsageImporter()

    func testMessageUsageUsesConfiguredTimezoneAndFinalCounterDate() throws {
        try withFolder { folder in
            try write(record(id: "msg_a", input: "10", output: "5", timestamp: "2026-09-16T14:59:00Z") +
                      record(id: "msg_a", input: "10", output: "20", timestamp: "2026-09-16T15:01:00.123Z"),
                      to: folder, file: "session.jsonl")
            let korea = ClaudeUsageImporter(calendar: calendar("Asia/Seoul"))
            XCTAssertEqual(try korea.read(folder: folder), [
                UsageSnapshot(sourceID: "claude:msg_a", totalTokens: 30, dailyTokens: ["2026-09-17": 30])
            ])
            let utc = ClaudeUsageImporter(calendar: calendar("UTC"))
            XCTAssertEqual(try utc.read(folder: folder).first?.dailyTokens, ["2026-09-16": 30])
        }
    }

    func testEqualCounterCopiesUseEarliestDateRegardlessOfFileOrder() throws {
        try withFolder { folder in
            try write(record(id: "msg_a", timestamp: "2026-09-18T01:00:00Z"), to: folder, file: "a-copy.jsonl")
            try write(record(id: "msg_a", timestamp: "2026-09-16T01:00:00Z"), to: folder, file: "z-original.jsonl")
            let reader = ClaudeUsageImporter(calendar: calendar("UTC"))
            XCTAssertEqual(try reader.read(folder: folder), [
                UsageSnapshot(sourceID: "claude:msg_a", totalTokens: 15, dailyTokens: ["2026-09-16": 15])
            ])
        }
    }

    func testHistoricImportKeepsRecordDateAndMissingTimestampsStayUndated() throws {
        try withFolder { folder in
            try write(record(id: "history", timestamp: "2020-02-01T23:00:00Z") +
                      record(id: "missing") + record(id: "invalid", timestamp: "not-a-timestamp"),
                      to: folder, file: "session.jsonl")
            let reader = ClaudeUsageImporter(calendar: calendar("UTC"))
            let snapshots = try reader.read(folder: folder)
            XCTAssertEqual(snapshots, [
                UsageSnapshot(sourceID: "claude:history", totalTokens: 15, dailyTokens: ["2020-02-01": 15]),
                UsageSnapshot(sourceID: "claude:invalid", totalTokens: 15),
                UsageSnapshot(sourceID: "claude:missing", totalTokens: 15)
            ])
            XCTAssertEqual(try reader.read(folder: folder), snapshots)
        }
    }

    func testUndatedLargerCounterDoesNotReuseAnEarlierIncompleteTimestamp() throws {
        try withFolder { folder in
            try write(record(id: "msg_a", output: "5", timestamp: "2026-09-16T23:59:00Z") +
                      record(id: "msg_a", output: "20"), to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "claude:msg_a", totalTokens: 30)])
        }
    }

    func testCacheReusesMetadataAndRecomputesChangedMessageDate() throws {
        try withFolder { folder in
            let reader = ClaudeUsageImporter(calendar: calendar("UTC"))
            try write(record(id: "msg_a", output: "10", timestamp: "2026-09-16T23:59:00Z"), to: folder, file: "session.jsonl")
            let file = folder.appendingPathComponent("session.jsonl")
            let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]!
            XCTAssertEqual(try reader.read(folder: folder).first?.dailyTokens, ["2026-09-16": 20])
            XCTAssertEqual(reader.parsedFileCount, 1)
            _ = try reader.read(folder: folder)
            XCTAssertEqual(reader.parsedFileCount, 1)
            // Restoring mtime after a same-size edit cannot serve stale parsed counters.
            try write(record(id: "msg_a", output: "20", timestamp: "2026-09-17T00:01:00Z"), to: folder, file: "session.jsonl")
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
            XCTAssertEqual(try reader.read(folder: folder).first?.dailyTokens, ["2026-09-17": 30])
            XCTAssertEqual(reader.parsedFileCount, 2)
            try FileManager.default.removeItem(at: file)
            XCTAssertEqual(try reader.read(folder: folder), [])
        }
    }

    @MainActor
    func testSharedImporterCanReadConcurrently() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(record(id: "msg_a"), to: folder, file: "session.jsonl")
        let reader = ClaudeUsageImporter()
        let results = try await withThrowingTaskGroup(of: [UsageSnapshot].self) { group in
            for _ in 0..<4 { group.addTask { try reader.read(folder: folder) } }
            var results: [[UsageSnapshot]] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy { $0 == [UsageSnapshot(sourceID: "claude:msg_a", totalTokens: 15)] })
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    func testCountsEachCacheCategoryOnceAndIgnoresNestedBreakdown() throws {
        try withFolder { folder in
            try write(record(id: "msg_cache", input: "7", output: "11", creation: "120", read: "900",
                             extra: ",\"cache_creation\":{\"ephemeral_5m_input_tokens\":20,\"ephemeral_1h_input_tokens\":100}"),
                      to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder), [UsageSnapshot(sourceID: "claude:msg_cache", totalTokens: 1_038)])
        }
    }

    func testDuplicatesAndStreamingGrowthMergeAcrossFilesAndSubagents() throws {
        try withFolder { folder in
            let project = folder.appendingPathComponent("projects/project")
            let subagents = project.appendingPathComponent("session/subagents")
            try write(record(id: "msg_a", input: "100", output: "2", creation: "20", read: "30") +
                      record(id: "msg_a", input: "100", output: "12", creation: "20", read: "30"),
                      to: project, file: "session.jsonl")
            try write(record(id: "msg_a", input: "100", output: "7", creation: "20", read: "30") +
                      record(id: "msg_child", input: "3", output: "4"),
                      to: subagents, file: "agent-test.jsonl")
            let expected = [
                UsageSnapshot(sourceID: "claude:msg_a", totalTokens: 162),
                UsageSnapshot(sourceID: "claude:msg_child", totalTokens: 7)
            ]
            XCTAssertEqual(try importer.read(folder: folder), expected)
            XCTAssertEqual(try importer.read(folder: folder), expected)
            XCTAssertEqual(try importer.read(folder: project), expected)
        }
    }

    func testMergesEachCounterIndependently() throws {
        try withFolder { folder in
            try write(record(id: "msg_a", input: "8", output: "2", creation: "30") +
                      record(id: "msg_a", input: "4", output: "9", creation: "10", read: "20"),
                      to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder).first?.totalTokens, 67)
        }
    }

    func testClaudeHomeLimitsReadingToProjects() throws {
        try withFolder { parent in
            let home = parent.appendingPathComponent(".claude")
            try write("broken history\n", to: home, file: "history.jsonl")
            try write("broken telemetry\n", to: home.appendingPathComponent("telemetry"), file: "events.jsonl")
            try write(record(id: "msg_a"), to: home.appendingPathComponent("projects/project"), file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: home).map(\.sourceID), ["claude:msg_a"])
        }
    }

    func testNewClaudeHomeAndEmptyFolderHaveNoUsage() throws {
        try withFolder { folder in
            XCTAssertEqual(try importer.read(folder: folder), [])
            let home = folder.appendingPathComponent(".claude")
            try write("not a transcript\n", to: home, file: "history.jsonl")
            XCTAssertEqual(try importer.read(folder: home), [])
        }
    }

    func testIgnoresUserAndMetadataRecordsAndUnbilledAssistantNotice() throws {
        try withFolder { folder in
            let data = """
            {"type":"user","message":{"usage":{"input_tokens":true}}}
            {"type":"summary","summary":"unrelated metadata"}
            {"type":"assistant","message":{"content":[]}}
            {"type":"assistant","message":{"usage":null}}

            """
            try write(data, to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder), [])
        }
    }

    func testRejectsInvalidNumericRepresentationsWithoutRounding() throws {
        for invalid in ["true", "false", "-1", "1.5", "1.0", "1e3", "\"12\"", "null", "[]",
                        "9223372036854775808", "9007199254740993.1", "1.0000000000000000000000000000000000000001"] {
            try withFolder { folder in
                try write(record(id: "msg_bad", input: invalid), to: folder, file: "session.jsonl")
                XCTAssertThrowsError(try importer.read(folder: folder), "Accepted \(invalid)")
            }
        }
    }

    func testPreservesLargeExactInt64AndRejectsAdditionOverflow() throws {
        try withFolder { folder in
            try write(record(id: "msg_large", input: "9223372036854775807", output: "0"), to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder).first?.totalTokens, Int64.max)
            try write(record(id: "msg_large", input: "9223372036854775807", output: "1"), to: folder, file: "session.jsonl")
            XCTAssertThrowsError(try importer.read(folder: folder))
        }
    }

    func testRejectsOverflowIntroducedByMergedCounters() throws {
        try withFolder { folder in
            try write(record(id: "msg_a", input: "9223372036854775807", output: "0") +
                      record(id: "msg_a", input: "0", output: "1"), to: folder, file: "session.jsonl")
            XCTAssertThrowsError(try importer.read(folder: folder))
        }
    }

    func testRejectsMalformedRelevantRecordsIncludingValidJSONWithoutNewline() throws {
        let invalid = [
            "{\"type\":\"assistant\"}",
            "{\"type\":\"assistant\",\"message\":\"invalid\"}",
            "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_a\",\"usage\":false}}",
            "{\"type\":\"assistant\",\"message\":{\"id\":\"\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}",
            "{\"type\":\"assistant\",\"message\":{\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}",
            "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_a\",\"usage\":{\"input_tokens\":1}}}"
        ]
        for data in invalid {
            try withFolder { folder in
                try write(data, to: folder, file: "session.jsonl")
                XCTAssertThrowsError(try importer.read(folder: folder))
            }
        }
    }

    func testPartialTrailingRecordIsIgnoredButMalformedTerminatedLineFails() throws {
        try withFolder { folder in
            let valid = record(id: "msg_a")
            try write(valid + "{\"type\":\"assistant\",", to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder).map(\.sourceID), ["claude:msg_a"])
            try write(valid + "{\"type\":\"assistant\",\n", to: folder, file: "session.jsonl")
            XCTAssertThrowsError(try importer.read(folder: folder))
        }
    }

    func testCompleteFinalRecordWithoutNewlineIsImported() throws {
        try withFolder { folder in
            try write(String(record(id: "msg_a").dropLast()), to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder).map(\.sourceID), ["claude:msg_a"])
        }
    }

    func testChunkBoundariesDoNotLoseRecords() throws {
        try withFolder { folder in
            let padding = String(repeating: "x", count: 150_000)
            let data = "{\"type\":\"user\",\"message\":{\"content\":\"\(padding)\"}}\n" + record(id: "msg_a")
            try write(data, to: folder, file: "session.jsonl")
            XCTAssertEqual(try importer.read(folder: folder).map(\.sourceID), ["claude:msg_a"])
        }
    }

    func testMissingFolderAndFileInsteadOfFolderFail() throws {
        try withFolder { folder in
            XCTAssertThrowsError(try importer.read(folder: folder.appendingPathComponent("missing")))
            try write(record(id: "msg_a"), to: folder, file: "session.jsonl")
            XCTAssertThrowsError(try importer.read(folder: folder.appendingPathComponent("session.jsonl")))
        }
    }

    func testUnreadableTranscriptFails() throws {
        try withFolder { folder in
            try write(record(id: "msg_a"), to: folder, file: "session.jsonl")
            _ = try importer.read(folder: folder)
            let file = folder.appendingPathComponent("session.jsonl")
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
            XCTAssertThrowsError(try importer.read(folder: folder))
        }
    }

    private func record(id: String, input: String = "10", output: String = "5",
                        creation: String = "0", read: String = "0", extra: String = "", timestamp: String? = nil) -> String {
        let field = timestamp.map { "\"timestamp\":\"\($0)\"," } ?? ""
        return "{\(field)\"type\":\"assistant\",\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cache_creation_input_tokens\":\(creation),\"cache_read_input_tokens\":\(read)\(extra)}}}\n"
    }

    private func write(_ text: String, to folder: URL, file: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(file))
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("claude-import-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }
}
