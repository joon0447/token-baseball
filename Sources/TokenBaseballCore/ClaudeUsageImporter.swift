import CoreFoundation
import Foundation

/// Reads only usage metadata from Claude Code's local session transcripts.
public struct ClaudeUsageImporter: Sendable {
    public init() {}

    public func read(folder: URL) throws -> [UsageSnapshot] {
        try Task.checkCancellation()
        let manager = FileManager.default
        try requireReadableDirectory(folder)
        let projects = folder.appendingPathComponent("projects", isDirectory: true)
        let root: URL
        if manager.fileExists(atPath: projects.path) {
            try requireReadableDirectory(projects)
            root = projects
        } else if folder.lastPathComponent == ".claude" {
            // A fresh Claude installation may have history/configuration but no sessions yet.
            return []
        } else {
            root = folder
        }

        var traversalError: Error?
        guard let files = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw ClaudeUsageImportError.folderUnavailable(root.path)
        }

        var usageByMessage: [String: TokenUsage] = [:]
        for case let file as URL in files {
            try Task.checkCancellation()
            guard file.pathExtension.lowercased() == "jsonl",
                  file.lastPathComponent != "history.jsonl" else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try readLines(file: file) { data, line, terminated in
                guard let (id, usage) = try parse(data, file: file, line: line, terminated: terminated) else {
                    return
                }
                let merged = usageByMessage[id]?.merging(usage) ?? usage
                _ = try merged.total(file: file.lastPathComponent, line: line)
                usageByMessage[id] = merged
            }
        }
        if traversalError != nil {
            throw ClaudeUsageImportError.folderUnavailable(root.path)
        }

        return try usageByMessage.keys.sorted().map { id in
            UsageSnapshot(
                sourceID: "claude:" + id,
                totalTokens: try usageByMessage[id]!.total(file: "Claude", line: 0)
            )
        }
    }

    private func requireReadableDirectory(_ folder: URL) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: folder.path) else {
            throw ClaudeUsageImportError.folderUnavailable(folder.path)
        }
    }

    private func readLines(
        file: URL,
        consume: (Data, Int, Bool) throws -> Void
    ) throws {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: file) }
        catch { throw ClaudeUsageImportError.fileUnavailable(file.lastPathComponent) }
        defer { try? handle.close() }

        // Bound transcript buffering independently of file size; only counters survive each line.
        let maximumLineBytes = 64 * 1_024 * 1_024
        var pending = Data()
        var line = 1
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do { chunk = try handle.read(upToCount: 64 * 1_024) ?? Data() }
            catch { throw ClaudeUsageImportError.fileUnavailable(file.lastPathComponent) }
            if chunk.isEmpty { break }
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 0x0A)
                let end = newline ?? chunk.endIndex
                guard pending.count + chunk.distance(from: start, to: end) <= maximumLineBytes else {
                    throw ClaudeUsageImportError.recordTooLarge(file: file.lastPathComponent, line: line)
                }
                pending.append(contentsOf: chunk[start..<end])
                guard let newline else { break }
                try consume(pending, line, true)
                pending.removeAll(keepingCapacity: true)
                line += 1
                start = chunk.index(after: newline)
            }
        }
        if !pending.isEmpty { try consume(pending, line, false) }
    }

    private func parse(
        _ data: Data,
        file: URL,
        line: Int,
        terminated: Bool
    ) throws -> (String, TokenUsage)? {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) { return nil }
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch {
            // A running session may be partway through appending its final JSONL record.
            if !terminated { return nil }
            throw ClaudeUsageImportError.invalidRecord(file: file.lastPathComponent, line: line)
        }
        guard let record = value as? [String: Any] else {
            throw ClaudeUsageImportError.invalidRecord(file: file.lastPathComponent, line: line)
        }
        guard record["type"] as? String == "assistant" else { return nil }
        guard let message = record["message"] as? [String: Any] else {
            throw ClaudeUsageImportError.invalidRecord(file: file.lastPathComponent, line: line)
        }
        // Synthetic assistant notices may have no billed usage.
        guard let rawUsage = message["usage"], !(rawUsage is NSNull) else { return nil }
        guard let usage = rawUsage as? [String: Any],
              let id = message["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageImportError.invalidRecord(file: file.lastPathComponent, line: line)
        }
        func count(_ key: String, required: Bool) throws -> Int64 {
            guard let raw = usage[key] else {
                if !required { return 0 }
                throw ClaudeUsageImportError.invalidRecord(file: file.lastPathComponent, line: line)
            }
            guard let number = raw as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["d", "f"].contains(String(cString: number.objCType)),
                  let count = Int64(number.stringValue), count >= 0 else {
                throw ClaudeUsageImportError.invalidRecord(file: file.lastPathComponent, line: line)
            }
            return count
        }
        let tokens = try TokenUsage(
            input: count("input_tokens", required: true),
            output: count("output_tokens", required: true),
            creation: count("cache_creation_input_tokens", required: false),
            read: count("cache_read_input_tokens", required: false)
        )
        _ = try tokens.total(file: file.lastPathComponent, line: line)
        return (id, tokens)
    }
}

private struct TokenUsage {
    let input: Int64
    let output: Int64
    let creation: Int64
    let read: Int64

    func merging(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: max(input, other.input),
            output: max(output, other.output),
            creation: max(creation, other.creation),
            read: max(read, other.read)
        )
    }

    func total(file: String, line: Int) throws -> Int64 {
        try [input, output, creation, read].reduce(Int64(0)) { total, count in
            let result = total.addingReportingOverflow(count)
            guard !result.overflow else {
                throw ClaudeUsageImportError.tokenOverflow(file: file, line: line)
            }
            return result.partialValue
        }
    }
}

public enum ClaudeUsageImportError: Error, LocalizedError, Sendable {
    case folderUnavailable(String)
    case fileUnavailable(String)
    case invalidRecord(file: String, line: Int)
    case tokenOverflow(file: String, line: Int)
    case recordTooLarge(file: String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .folderUnavailable:
            "Claude 사용량 폴더를 읽을 수 없습니다. 폴더 위치와 접근 권한을 확인해 주세요."
        case .fileUnavailable(let file):
            "Claude 기록 파일 \(file)을 읽을 수 없습니다. 다시 시도해 주세요."
        case .invalidRecord(let file, let line):
            "Claude 기록 \(file)의 \(line)번째 줄에 올바르지 않은 사용량 데이터가 있습니다."
        case .tokenOverflow(let file, let line):
            "Claude 기록 \(file)의 \(line)번째 줄에 처리할 수 있는 범위를 넘는 토큰 수가 있습니다."
        case .recordTooLarge(let file, let line):
            "Claude 기록 \(file)의 \(line)번째 줄이 읽을 수 있는 크기를 넘었습니다."
        }
    }
}
