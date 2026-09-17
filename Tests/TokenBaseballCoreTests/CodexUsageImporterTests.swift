import Foundation
import XCTest
@testable import TokenBaseballCore

final class CodexUsageImporterTests: XCTestCase {
    private let importer = CodexUsageImporter()

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

    private func tokens(_ value: String) -> String {
        #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":"# + value + #"}}}}"#
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
