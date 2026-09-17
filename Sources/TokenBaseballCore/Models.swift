import Foundation

public enum CardTier: String, CaseIterable, Codable, Identifiable, Sendable {
    case rookie, allStar, legend

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rookie: "루키"
        case .allStar: "올스타"
        case .legend: "레전드"
        }
    }

}

public enum FieldPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case pitcher, catcher, firstBase, secondBase, thirdBase, shortstop, leftField, centerField, rightField

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pitcher: "투수"
        case .catcher: "포수"
        case .firstBase: "1루수"
        case .secondBase: "2루수"
        case .thirdBase: "3루수"
        case .shortstop: "유격수"
        case .leftField: "좌익수"
        case .centerField: "중견수"
        case .rightField: "우익수"
        }
    }
    public var abbreviation: String {
        switch self {
        case .pitcher: "P"
        case .catcher: "C"
        case .firstBase: "1B"
        case .secondBase: "2B"
        case .thirdBase: "3B"
        case .shortstop: "SS"
        case .leftField: "LF"
        case .centerField: "CF"
        case .rightField: "RF"
        }
    }
}

public enum DrawPolicy {
    /// Token-based draw rules; raw usage counters remain unchanged.
    public static let tokensPerDraw: Int64 = 50_000_000
    public static let rookieWeight = 75
    public static let allStarWeight = 20
    public static let legendWeight = 5
}

public enum CardOrigin: String, Codable, Sendable {
    case starter, draw, legacy
}

public struct PlayerCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let catalogID: String
    public let defaultName: String
    public var customName: String?
    public let tier: CardTier
    public let position: FieldPosition
    public let origin: CardOrigin
    public var photoData: Data?
    public var name: String { customName ?? defaultName }

    public init(id: UUID = UUID(), catalogID: String, defaultName: String, customName: String? = nil,
                tier: CardTier, position: FieldPosition, photoData: Data? = nil, origin: CardOrigin = .legacy) {
        self.id = id
        self.catalogID = catalogID
        self.defaultName = defaultName
        self.customName = customName
        self.tier = tier
        self.position = position
        self.photoData = photoData
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id, catalogID, defaultName, customName, tier, position, photoData, origin
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        catalogID = try values.decode(String.self, forKey: .catalogID)
        defaultName = try values.decode(String.self, forKey: .defaultName)
        customName = try values.decodeIfPresent(String.self, forKey: .customName)
        tier = try values.decode(CardTier.self, forKey: .tier)
        position = try values.decode(FieldPosition.self, forKey: .position)
        photoData = try values.decodeIfPresent(Data.self, forKey: .photoData)
        // Schema 1 cards predate acquisition provenance.
        origin = try values.decodeIfPresent(CardOrigin.self, forKey: .origin) ?? .legacy
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let sourceID: String
    public let totalTokens: Int64
    public let dailyTokens: [String: Int64]

    public init(sourceID: String, totalTokens: Int64, dailyTokens: [String: Int64] = [:]) {
        self.sourceID = sourceID
        self.totalTokens = totalTokens
        self.dailyTokens = dailyTokens
    }
}

public struct GameState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var totalTokens: Int64
    public var sourceTotals: [String: Int64]
    public var sourceDailyTotals: [String: [String: Int64]]
    public var openedDraws: Int64
    public var starterGrantComplete: Bool
    public var cards: [PlayerCard]
    public var lineup: [String: UUID]
    public var lastImport: Date?
    public var importFolders: [String: String]
    public var availableDraws: Int64 { totalTokens / DrawPolicy.tokensPerDraw - openedDraws }

    public init(schemaVersion: Int = currentSchemaVersion, totalTokens: Int64 = 0,
                sourceTotals: [String: Int64] = [:], sourceDailyTotals: [String: [String: Int64]] = [:],
                openedDraws: Int64 = 0, starterGrantComplete: Bool = false,
                cards: [PlayerCard] = [], lineup: [String: UUID] = [:],
                lastImport: Date? = nil, importFolders: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.totalTokens = totalTokens
        self.sourceTotals = sourceTotals
        self.sourceDailyTotals = sourceDailyTotals
        self.openedDraws = openedDraws
        self.starterGrantComplete = starterGrantComplete
        self.cards = cards
        self.lineup = lineup
        self.lastImport = lastImport
        self.importFolders = importFolders
    }

    public func tokens(on dayKey: String) -> Int64 {
        // Valid snapshots have nonnegative daily subtotals bounded by totalTokens.
        sourceDailyTotals.values.reduce(0) { total, days in
            let sum = total.addingReportingOverflow(days[dayKey] ?? 0)
            return sum.overflow ? Int64.max : sum.partialValue
        }
    }
}

public enum GameError: LocalizedError, Equatable {
    case invalidUsage
    case arithmeticOverflow
    case noDrawsAvailable
    case cardNotFound
    case cardAlreadyAssigned
    case positionMismatch
    case invalidName
    case invalidFolder
    case unsupportedSchema(Int)
    case corruptSave
    case staleSave
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUsage: "사용량 기록에는 유효한 출처와 0 이상의 토큰 수가 필요해요."
        case .arithmeticOverflow: "토큰 수가 처리 가능한 범위를 넘었어요."
        case .noDrawsAvailable: "사용 기록을 더 쌓으면 새로운 선수를 뽑을 수 있어요."
        case .cardNotFound: "보유한 카드에서 해당 선수를 찾을 수 없어요."
        case .cardAlreadyAssigned: "이미 다른 포지션에 배치한 선수예요."
        case .positionMismatch: "선수는 카드에 표시된 포지션에만 배치할 수 있어요."
        case .invalidName: "이름은 앞뒤 공백을 제외하고 1~30자로 입력해 주세요."
        case .invalidFolder: "사용량을 읽을 폴더 경로를 확인해 주세요."
        case let .unsupportedSchema(version): "저장 파일 버전 \(version)은 이 앱에서 열 수 없어요. 원본 파일은 보존했어요."
        case .corruptSave: "저장 파일을 읽을 수 없어요. 원본 파일은 보존했어요."
        case .staleSave: "다른 실행에서 저장 데이터가 바뀌었어요. 앱을 다시 열어 최신 기록을 불러온 뒤 시도해 주세요."
        case let .invalidState(reason): "저장 데이터가 올바르지 않아요: \(reason). 원본 파일은 보존했어요."
        }
    }
}

/// Small fictional-name pool, independent of card tier and position.
enum PlayerGenerator {
    static let names = [
        "강도윤", "문하준", "서지호", "윤태오", "한시우", "정이준", "백선우", "오유찬", "임건우",
        "고태준", "신도현", "박재윤", "이서진", "홍지완", "송현우", "권우진", "차민준", "최은호",
        "류강산", "조해솔", "김여준", "남승재", "양찬율", "하정우", "유지한", "장하람", "배로운"
    ]

    static func make(tier: CardTier, position: FieldPosition, randomIndex: (Int) -> Int) -> PlayerCard {
        let id = UUID()
        return PlayerCard(id: id, catalogID: "generated-" + id.uuidString,
                          defaultName: names[index(randomIndex, count: names.count)], tier: tier, position: position, origin: .draw)
    }

    static func grantStarters(to state: inout GameState, randomIndex: (Int) -> Int) {
        var names = self.names
        for position in FieldPosition.allCases {
            let id = UUID()
            let name = names.remove(at: index(randomIndex, count: names.count))
            let starter = PlayerCard(id: id, catalogID: "generated-" + id.uuidString,
                                     defaultName: name, tier: .rookie, position: position, origin: .starter)
            state.cards.append(starter)
            let existing = state.lineup[position.rawValue].flatMap { id in state.cards.first { $0.id == id } }
            if existing?.position != position { state.lineup[position.rawValue] = starter.id }
        }
        state.starterGrantComplete = true
    }

    static func index(_ randomIndex: (Int) -> Int, count: Int) -> Int {
        // Keep an injected source from indexing outside the collection.
        min(max(randomIndex(count), 0), count - 1)
    }
}
