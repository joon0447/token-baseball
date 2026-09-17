import CoreFoundation
import Darwin
import Foundation

public protocol SnapshotPersistence {
    func load() throws -> GameState?
    func save(_ state: GameState) throws
}

/// A single store's disk session. Give each GameStore its own instance so its
/// last-loaded snapshot cannot be replaced by a different store's load/save.
public final class JSONDiskPersistence: SnapshotPersistence {
    public let url: URL
    private var expectedSnapshot: GameState?

    public init(url: URL) { self.url = url }

    public func load() throws -> GameState? {
        try withFileLock {
            let snapshot = try readSnapshot()
            expectedSnapshot = snapshot
            return snapshot
        }
    }

    private func readSnapshot() throws -> GameState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GameError.corruptSave
            }
            object = parsed
        } catch {
            throw GameError.corruptSave
        }
        let schemaVersion = try exactNonnegativeInteger(object["schemaVersion"])
        guard schemaVersion == Int64(GameState.currentSchemaVersion) else {
            throw GameError.unsupportedSchema(Int(schemaVersion))
        }
        // JSONDecoder can round large fractional literals while decoding Int64.
        // Check the original JSON number types before decoding the stored ledger.
        for key in ["totalTokens", "earnedCurrency", "spentCurrency"] {
            _ = try exactNonnegativeInteger(object[key])
        }
        guard let sourceTotals = object["sourceTotals"] as? [String: Any] else { throw GameError.corruptSave }
        for total in sourceTotals.values { _ = try exactNonnegativeInteger(total) }
        let state: GameState
        do {
            state = try JSONDecoder().decode(GameState.self, from: data)
        } catch {
            throw GameError.corruptSave
        }
        try state.validate()
        return state
    }

    public func save(_ state: GameState) throws {
        try state.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try withFileLock {
            // Reading here must not advance the expected snapshot on a conflict.
            // Invalid or unsupported files also remain untouched.
            guard try readSnapshot() == expectedSnapshot else { throw GameError.staleSave }
            try data.write(to: url, options: .atomic)
            expectedSnapshot = state
        }
    }

    private func exactNonnegativeInteger(_ value: Any?) throws -> Int64 {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              let integer = Int64(number.stringValue), integer >= 0 else {
            throw GameError.corruptSave
        }
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
        // Keep the sidecar after unlocking; deleting it could split concurrent
        // writers across different lock-file inodes.
        return try body()
    }
}

extension GameState {
    /// Reject inconsistent snapshots before displaying or mutating their balances.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw GameError.unsupportedSchema(schemaVersion) }
        guard totalTokens >= 0, earnedCurrency >= 0, spentCurrency >= 0, spentCurrency <= earnedCurrency else {
            throw GameError.invalidState("재화 또는 토큰 수가 유효하지 않음")
        }
        guard earnedCurrency == totalTokens / Self.tokensPerCurrency else {
            throw GameError.invalidState("토큰과 누적 적립액이 일치하지 않음")
        }
        var sourceSum: Int64 = 0
        for (source, total) in sourceTotals {
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, total >= 0 else {
                throw GameError.invalidState("사용량 출처가 유효하지 않음")
            }
            let sum = sourceSum.addingReportingOverflow(total)
            guard !sum.overflow else { throw GameError.arithmeticOverflow }
            sourceSum = sum.partialValue
        }
        guard sourceSum == totalTokens else { throw GameError.invalidState("출처별 사용량 합계가 일치하지 않음") }
        guard Set(cards.map(\.id)).count == cards.count, Set(cards.map(\.catalogID)).count == cards.count else {
            throw GameError.invalidState("보유 카드가 중복됨")
        }
        var purchaseSum: Int64 = 0
        for card in cards {
            guard let offer = Catalog.offers.first(where: { $0.id == card.catalogID }),
                  card.defaultName == offer.name, card.tier == offer.tier, card.position == offer.position else {
                throw GameError.invalidState("카드 기본 정보가 유효하지 않음")
            }
            if let name = card.customName {
                guard !name.isEmpty, name.count <= 30, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw GameError.invalidState("선수 이름이 유효하지 않음")
                }
            }
            let sum = purchaseSum.addingReportingOverflow(card.tier.price)
            guard !sum.overflow else { throw GameError.arithmeticOverflow }
            purchaseSum = sum.partialValue
        }
        guard purchaseSum == spentCurrency else { throw GameError.invalidState("구매 내역과 사용 재화가 일치하지 않음") }
        let cardIDs = Set(cards.map(\.id))
        guard lineup.keys.allSatisfy({ FieldPosition(rawValue: $0) != nil }),
              lineup.values.allSatisfy({ cardIDs.contains($0) }),
              Set(lineup.values).count == lineup.count else {
            throw GameError.invalidState("선수단 배치가 유효하지 않음")
        }
        guard importFolders.allSatisfy({ source, path in
            ["codex", "claude"].contains(source) && (path as NSString).isAbsolutePath
        }) else { throw GameError.invalidState("연동 폴더가 유효하지 않음") }
    }
}
