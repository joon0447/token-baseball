import CoreFoundation
import Darwin
import Foundation

public protocol SnapshotPersistence {
    func load() throws -> GameState?
    func save(_ state: GameState) throws
}

/// A disk session for one GameStore. Raw snapshots and a process lock prevent
/// stale writers from replacing newer saves, including during schema migration.
public final class JSONDiskPersistence: SnapshotPersistence {
    public let url: URL
    private var expectedData: Data?

    public init(url: URL) { self.url = url }

    public func load() throws -> GameState? {
        try withFileLock {
            guard let data = try readData() else {
                expectedData = nil
                return nil
            }
            switch try decode(data) {
            case let .current(state):
                expectedData = data
                return state
            case let .legacy(legacy):
                var state = legacy.migrated()
                PlayerGenerator.grantStarters(to: &state) { Int.random(in: 0..<$0) }
                try state.validate()
                let migratedData = try encoded(state)
                try preserveLegacyBackup(data)
                try migratedData.write(to: url, options: .atomic)
                expectedData = migratedData
                return state
            }
        }
    }

    public func save(_ state: GameState) throws {
        try state.validate()
        let data = try encoded(state)
        try withFileLock {
            let actual = try readData()
            // A corrupt or unsupported file is never replaced, even by a caller
            // that previously loaded a valid snapshot.
            if let actual { _ = try decode(actual) }
            guard actual == expectedData else { throw GameError.staleSave }
            try data.write(to: url, options: .atomic)
            expectedData = data
        }
    }

    private func readData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func encoded(_ state: GameState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    private enum StoredSnapshot {
        case current(GameState)
        case legacy(LegacyGameState)
    }

    private func decode(_ data: Data) throws -> StoredSnapshot {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GameError.corruptSave
            }
            object = parsed
        } catch { throw GameError.corruptSave }
        let version = try exactNonnegativeInteger(object["schemaVersion"])
        guard version == 1 || version == Int64(GameState.currentSchemaVersion) else {
            throw GameError.unsupportedSchema(Int(version))
        }
        // JSONDecoder may round large fractional literals into Int64. Validate
        // the original JSON number types before decoding every stored counter.
        let scalarKeys = version == 1 ? ["totalTokens", "earnedCurrency", "spentCurrency"] : ["totalTokens", "openedDraws"]
        for key in scalarKeys { _ = try exactNonnegativeInteger(object[key]) }
        guard let sources = object["sourceTotals"] as? [String: Any] else { throw GameError.corruptSave }
        for value in sources.values { _ = try exactNonnegativeInteger(value) }
        if version == 2 {
            guard let sourceDays = object["sourceDailyTotals"] as? [String: Any] else { throw GameError.corruptSave }
            for value in sourceDays.values {
                guard let days = value as? [String: Any] else { throw GameError.corruptSave }
                for count in days.values { _ = try exactNonnegativeInteger(count) }
            }
        }
        let decoder = JSONDecoder()
        if version == 1 {
            let legacy: LegacyGameState
            do { legacy = try decoder.decode(LegacyGameState.self, from: data) }
            catch { throw GameError.corruptSave }
            try legacy.validate()
            return .legacy(legacy)
        }
        let state: GameState
        do { state = try decoder.decode(GameState.self, from: data) }
        catch { throw GameError.corruptSave }
        try state.validate()
        return .current(state)
    }

    private func preserveLegacyBackup(_ data: Data) throws {
        let backup = url.appendingPathExtension("v1.backup")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".migration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        // Linking a complete temporary file is atomic and cannot replace an
        // existing backup. Removing the temporary link retains the backup.
        do { try FileManager.default.linkItem(at: temporary, to: backup) }
        catch {
            guard FileManager.default.fileExists(atPath: backup.path) else { throw error }
        }
    }

    private func exactNonnegativeInteger(_ value: Any?) throws -> Int64 {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              let integer = Int64(number.stringValue), integer >= 0 else { throw GameError.corruptSave }
        return integer
    }

    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = lockURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { errno = EINVAL; return -1 }
            return Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = Darwin.close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        // Keep the sidecar: deleting it could split writers across lock inodes.
        return try body()
    }
}

private struct LegacyGameState: Decodable {
    let schemaVersion: Int
    let totalTokens: Int64
    let earnedCurrency: Int64
    let spentCurrency: Int64
    let cards: [PlayerCard]
    let lineup: [String: UUID]
    let sourceTotals: [String: Int64]
    let lastImport: Date?
    let importFolders: [String: String]

    func validate() throws {
        try GameState.validateUsage(totalTokens: totalTokens, sources: sourceTotals, daily: [:])
        guard schemaVersion == 1, earnedCurrency == totalTokens / 1_000,
              spentCurrency >= 0, spentCurrency <= earnedCurrency else {
            throw GameError.invalidState("이전 재화 기록이 유효하지 않음")
        }
        try GameState.validateCards(cards, lineup: lineup, enforcePositions: false)
        guard Set(cards.map(\.catalogID)).count == cards.count else { throw GameError.invalidState("이전 카드가 중복됨") }
        var sum: Int64 = 0
        for card in cards {
            let price: Int64 = card.tier == .rookie ? 10 : card.tier == .allStar ? 30 : 100
            let next = sum.addingReportingOverflow(price)
            guard !next.overflow else { throw GameError.arithmeticOverflow }
            sum = next.partialValue
        }
        guard sum == spentCurrency else { throw GameError.invalidState("이전 구매 기록이 일치하지 않음") }
        try GameState.validateFolders(importFolders)
    }

    func migrated() -> GameState {
        GameState(totalTokens: totalTokens, sourceTotals: sourceTotals, cards: cards,
                  lineup: lineup, lastImport: lastImport, importFolders: importFolders)
    }
}

extension GameState {
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw GameError.unsupportedSchema(schemaVersion) }
        try Self.validateUsage(totalTokens: totalTokens, sources: sourceTotals, daily: sourceDailyTotals)
        guard openedDraws >= 0, openedDraws <= totalTokens / DrawPolicy.tokensPerDraw else {
            throw GameError.invalidState("선수 뽑기 횟수가 유효하지 않음")
        }
        let starters = cards.filter { $0.origin == .starter }
        guard starterGrantComplete, starters.count == FieldPosition.allCases.count,
              Set(starters.map(\.position)) == Set(FieldPosition.allCases),
              starters.allSatisfy({ $0.tier == .rookie }) else {
            throw GameError.invalidState("시작 선수 지급 기록이 유효하지 않음")
        }
        guard Int64(cards.filter { $0.origin == .draw }.count) == openedDraws else {
            throw GameError.invalidState("뽑기 횟수와 획득한 카드 수가 일치하지 않음")
        }
        try Self.validateCards(cards, lineup: lineup, enforcePositions: true)
        try Self.validateFolders(importFolders)
    }

    fileprivate static func validateUsage(totalTokens: Int64, sources: [String: Int64], daily: [String: [String: Int64]]) throws {
        guard totalTokens >= 0 else { throw GameError.invalidUsage }
        var sourceSum: Int64 = 0
        for (source, total) in sources {
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, total >= 0 else { throw GameError.invalidUsage }
            let sum = sourceSum.addingReportingOverflow(total)
            guard !sum.overflow else { throw GameError.arithmeticOverflow }
            sourceSum = sum.partialValue
        }
        guard sourceSum == totalTokens else { throw GameError.invalidState("출처별 사용량 합계가 일치하지 않음") }
        for (source, days) in daily {
            guard let total = sources[source] else { throw GameError.invalidUsage }
            var daySum: Int64 = 0
            for (day, count) in days {
                guard isValidDayKey(day), count >= 0 else { throw GameError.invalidUsage }
                let sum = daySum.addingReportingOverflow(count)
                guard !sum.overflow else { throw GameError.arithmeticOverflow }
                daySum = sum.partialValue
            }
            guard daySum <= total else { throw GameError.invalidUsage }
        }
    }

    static func isValidDayKey(_ key: String) -> Bool {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              key.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 45 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              year >= 1, (1...12).contains(month), day >= 1 else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= lengths[month - 1]
    }

    fileprivate static func validateCards(_ cards: [PlayerCard], lineup: [String: UUID], enforcePositions: Bool) throws {
        guard Set(cards.map(\.id)).count == cards.count else { throw GameError.invalidState("보유 카드가 중복됨") }
        for card in cards {
            guard !card.catalogID.isEmpty, !card.defaultName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  card.defaultName.count <= 30 else { throw GameError.invalidState("카드 기본 정보가 유효하지 않음") }
            if let name = card.customName {
                guard !name.isEmpty, name.count <= 30, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw GameError.invalidState("선수 이름이 유효하지 않음")
                }
            }
        }
        guard Set(lineup.values).count == lineup.count else { throw GameError.invalidState("선수단 카드가 중복됨") }
        for (rawPosition, id) in lineup {
            guard let position = FieldPosition(rawValue: rawPosition), let card = cards.first(where: { $0.id == id }),
                  !enforcePositions || card.position == position else {
                throw GameError.invalidState("선수단 배치가 유효하지 않음")
            }
        }
    }

    fileprivate static func validateFolders(_ folders: [String: String]) throws {
        guard folders.allSatisfy({ source, path in
            ["codex", "claude"].contains(source) && (path as NSString).isAbsolutePath
        }) else { throw GameError.invalidState("연동 폴더가 유효하지 않음") }
    }
}
