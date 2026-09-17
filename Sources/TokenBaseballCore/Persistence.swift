import Foundation

public protocol SnapshotPersistence {
    func load() throws -> GameState?
    func save(_ state: GameState) throws
}

public final class JSONDiskPersistence: SnapshotPersistence {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> GameState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let envelope: SchemaEnvelope
        do {
            envelope = try decoder.decode(SchemaEnvelope.self, from: data)
        } catch {
            throw GameError.corruptSave
        }
        guard envelope.schemaVersion == GameState.currentSchemaVersion else {
            throw GameError.unsupportedSchema(envelope.schemaVersion)
        }
        let state: GameState
        do {
            state = try decoder.decode(GameState.self, from: data)
        } catch {
            throw GameError.corruptSave
        }
        try state.validate()
        return state
    }

    public func save(_ state: GameState) throws {
        try state.validate()
        // Never silently replace a file that this version cannot read.
        _ = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private struct SchemaEnvelope: Decodable {
        let schemaVersion: Int
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
