import CoreFoundation
import Foundation

/// Reads cumulative token counts from user-selected Codex rollout files.
/// This local file format is not a stable, public usage API.
public struct CodexUsageImporter: Sendable {
    private static let maximumLineBytes = 16 * 1_024 * 1_024
    private static let maximumReadBytes = 8 * 1_024 * 1_024 * 1_024
    private static let maximumFiles = 10_000
    private static let maximumEntries = 100_000

    public init() {}

    /// Returns one maximum cumulative count per session, including archived copies.
    /// Throws without returning partial results when any complete record is invalid.
    public func read(folder: URL) throws -> [UsageSnapshot] {
        try Task.checkCancellation()
        guard folder.isFileURL else { throw CodexUsageImportError.invalidFolder }
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            throw CodexUsageImportError.invalidFolder
        }
        guard isDirectory.boolValue else { throw CodexUsageImportError.invalidFolder }

        let selectedFolder = folder.standardizedFileURL
        let namedRoots = ["sessions", "archived_sessions"].map {
            selectedFolder.appendingPathComponent($0, isDirectory: true)
        }
        let availableRoots = try namedRoots.filter { url in
            guard manager.fileExists(atPath: url.path) else { return false }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        // Never fall back to history.jsonl or unrelated files under a Codex home.
        let roots = !availableRoots.isEmpty || selectedFolder.lastPathComponent == ".codex"
            ? availableRoots : [selectedFolder]
        let files = try rolloutFiles(in: roots)
        var totals: [String: Int64] = [:]
        var bytesRead = 0
        for file in files {
            try Task.checkCancellation()
            if let session = try readFile(file, bytesRead: &bytesRead) {
                totals[session.id] = max(totals[session.id] ?? 0, session.tokens)
            }
        }
        return totals.keys.sorted().map { UsageSnapshot(sourceID: "codex:" + $0, totalTokens: totals[$0]!) }
    }

    private func rolloutFiles(in roots: [URL]) throws -> [URL] {
        var files: [URL] = []
        var entries = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        for root in roots {
            try Task.checkCancellation()
            var traversalError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in
                    traversalError = error
                    return false
                }
            ) else { throw CodexUsageImportError.unreadableFolder }
            for case let file as URL in enumerator {
                try Task.checkCancellation()
                entries += 1
                guard entries <= Self.maximumEntries else { throw CodexUsageImportError.resourceLimit }
                let values = try file.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true, file.pathExtension.lowercased() == "jsonl" else { continue }
                files.append(file)
                guard files.count <= Self.maximumFiles else { throw CodexUsageImportError.resourceLimit }
            }
            if traversalError != nil { throw CodexUsageImportError.unreadableFolder }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func readFile(_ file: URL, bytesRead: inout Int) throws -> (id: String, tokens: Int64)? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var pending = Data()
        var sessionID: String?
        var maximumTokens: Int64?
        var lineNumber = 0
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            bytesRead += chunk.count
            guard bytesRead <= Self.maximumReadBytes else { throw CodexUsageImportError.resourceLimit }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[..<newline])
                guard line.count <= Self.maximumLineBytes else { throw CodexUsageImportError.resourceLimit }
                lineNumber += 1
                try parse(line, complete: true, lineNumber: lineNumber,
                          sessionID: &sessionID, maximumTokens: &maximumTokens)
                pending.removeSubrange(...newline)
            }
            guard pending.count <= Self.maximumLineBytes else { throw CodexUsageImportError.resourceLimit }
        }
        if !pending.isEmpty {
            try parse(pending, complete: false, lineNumber: lineNumber + 1,
                      sessionID: &sessionID, maximumTokens: &maximumTokens)
        }
        guard let maximumTokens else { return nil }
        guard let sessionID else { throw CodexUsageImportError.missingSessionMetadata }
        return (sessionID, maximumTokens)
    }

    private func parse(_ line: Data, complete: Bool, lineNumber: Int,
                       sessionID: inout String?, maximumTokens: inout Int64?) throws {
        if line.allSatisfy({ [0x20, 0x09, 0x0D].contains($0) }) { return }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: line, options: .fragmentsAllowed)
        } catch {
            // A writer may still be appending the final unterminated JSON line.
            if !complete { return }
            throw CodexUsageImportError.malformedRecord(line: lineNumber)
        }
        guard let record = value as? [String: Any] else {
            throw CodexUsageImportError.malformedRecord(line: lineNumber)
        }
        switch record["type"] as? String {
        case "session_meta":
            guard let payload = record["payload"] as? [String: Any] else {
                throw CodexUsageImportError.invalidSessionMetadata(line: lineNumber)
            }
            // Desktop transcripts can append new metadata IDs on resume while
            // retaining a stable session_id. Older CLI records expose only id.
            let rawID = payload["session_id"] ?? payload["id"]
            guard let id = rawID as? String,
                  !id.isEmpty, id.utf8.count <= 256,
                  id.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
                throw CodexUsageImportError.invalidSessionMetadata(line: lineNumber)
            }
            if let sessionID, sessionID != id {
                throw CodexUsageImportError.invalidSessionMetadata(line: lineNumber)
            }
            sessionID = id
        case "event_msg":
            guard let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else { return }
            // Codex can emit rate-limit-only events before it has usage information.
            if payload["info"] is NSNull { return }
            guard let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any],
                  let number = usage["total_tokens"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: number.objCType)),
                  let tokens = Int64(number.stringValue), tokens >= 0 else {
                throw CodexUsageImportError.invalidTokenCount(line: lineNumber)
            }
            maximumTokens = max(maximumTokens ?? 0, tokens)
        default:
            break
        }
    }
}

public enum CodexUsageImportError: LocalizedError, Equatable {
    case invalidFolder
    case unreadableFolder
    case malformedRecord(line: Int)
    case invalidSessionMetadata(line: Int)
    case missingSessionMetadata
    case invalidTokenCount(line: Int)
    case resourceLimit

    public var errorDescription: String? {
        switch self {
        case .invalidFolder:
            "Codex 기록이 있는 폴더를 선택해 주세요."
        case .unreadableFolder:
            "Codex 기록 폴더를 읽을 수 없어요. 접근 권한을 확인해 주세요."
        case let .malformedRecord(line):
            "Codex 기록의 \(line)번째 줄을 읽을 수 없어 사용량을 반영하지 않았어요."
        case let .invalidSessionMetadata(line):
            "Codex 기록의 \(line)번째 줄에 올바른 세션 정보가 없어 사용량을 반영하지 않았어요."
        case .missingSessionMetadata:
            "세션 정보가 없는 Codex 사용량 기록이 있어 사용량을 반영하지 않았어요."
        case let .invalidTokenCount(line):
            "Codex 기록의 \(line)번째 줄에 올바른 토큰 수가 없어 사용량을 반영하지 않았어요."
        case .resourceLimit:
            "Codex 기록이 한 번에 읽을 수 있는 크기를 넘었어요. 더 작은 기록 폴더를 선택해 주세요."
        }
    }
}
