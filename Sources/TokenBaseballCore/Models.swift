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
    public var price: Int64 {
        switch self {
        case .rookie: 10
        case .allStar: 30
        case .legend: 100
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

public struct CardOffer: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let tier: CardTier
    public let position: FieldPosition
    public var price: Int64 { tier.price }

    public init(id: String, name: String, tier: CardTier, position: FieldPosition) {
        self.id = id
        self.name = name
        self.tier = tier
        self.position = position
    }
}

public enum Catalog {
    /// Fictional players. Catalog identifiers remain stable across app launches.
    public static let offers: [CardOffer] = {
        let names = [
            ["강도윤", "문하준", "서지호", "윤태오", "한시우", "정이준", "백선우", "오유찬", "임건우"],
            ["고태준", "신도현", "박재윤", "이서진", "홍지완", "송현우", "권우진", "차민준", "최은호"],
            ["류강산", "조해솔", "김여준", "남승재", "양찬율", "하정우", "유지한", "장하람", "배로운"]
        ]
        return CardTier.allCases.enumerated().flatMap { tierIndex, tier in
            FieldPosition.allCases.enumerated().map { positionIndex, position in
                CardOffer(id: "\(tier.rawValue)-\(position.rawValue)",
                          name: names[tierIndex][positionIndex], tier: tier, position: position)
            }
        }
    }()
}

public struct PlayerCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let catalogID: String
    public let defaultName: String
    public var customName: String?
    public let tier: CardTier
    public let position: FieldPosition
    public var photoData: Data?
    public var name: String { customName ?? defaultName }

    public init(id: UUID = UUID(), catalogID: String, defaultName: String, customName: String? = nil,
                tier: CardTier, position: FieldPosition, photoData: Data? = nil) {
        self.id = id
        self.catalogID = catalogID
        self.defaultName = defaultName
        self.customName = customName
        self.tier = tier
        self.position = position
        self.photoData = photoData
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
    public static let currentSchemaVersion = 1
    public static let tokensPerCurrency: Int64 = 1_000
    public var schemaVersion: Int
    public var totalTokens: Int64
    public var earnedCurrency: Int64
    public var spentCurrency: Int64
    public var balance: Int64 { earnedCurrency - spentCurrency }
    public var cards: [PlayerCard]
    public var lineup: [String: UUID]
    public var sourceTotals: [String: Int64]
    public var lastImport: Date?
    public var importFolders: [String: String]

    public init(schemaVersion: Int = currentSchemaVersion, totalTokens: Int64 = 0,
                earnedCurrency: Int64 = 0, spentCurrency: Int64 = 0, cards: [PlayerCard] = [],
                lineup: [String: UUID] = [:], sourceTotals: [String: Int64] = [:],
                lastImport: Date? = nil, importFolders: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.totalTokens = totalTokens
        self.earnedCurrency = earnedCurrency
        self.spentCurrency = spentCurrency
        self.cards = cards
        self.lineup = lineup
        self.sourceTotals = sourceTotals
        self.lastImport = lastImport
        self.importFolders = importFolders
    }
}

public enum GameError: LocalizedError, Equatable {
    case invalidUsage
    case arithmeticOverflow
    case unknownOffer
    case alreadyOwned
    case insufficientFunds(required: Int64, available: Int64)
    case cardNotFound
    case cardAlreadyAssigned
    case invalidName
    case invalidFolder
    case unsupportedSchema(Int)
    case corruptSave
    case staleSave
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUsage: "사용량 기록에는 유효한 출처와 0 이상의 토큰 수가 필요해요."
        case .arithmeticOverflow: "토큰 또는 재화 수가 처리 가능한 범위를 넘었어요."
        case .unknownOffer: "상점에서 해당 카드를 찾을 수 없어요."
        case .alreadyOwned: "이미 보유한 카드예요."
        case let .insufficientFunds(required, available): "구매에 \(required)볼이 필요해요. 현재 잔액은 \(available)볼이에요."
        case .cardNotFound: "보유한 카드에서 해당 선수를 찾을 수 없어요."
        case .cardAlreadyAssigned: "이미 다른 포지션에 배치한 선수예요. 먼저 해당 포지션에서 제외해 주세요."
        case .invalidName: "이름은 앞뒤 공백을 제외하고 1~30자로 입력해 주세요."
        case .invalidFolder: "사용량을 읽을 폴더 경로를 확인해 주세요."
        case let .unsupportedSchema(version): "저장 파일 버전 \(version)은 이 앱에서 열 수 없어요. 원본 파일은 보존했어요."
        case .corruptSave: "저장 파일을 읽을 수 없어요. 원본 파일은 보존했어요."
        case .staleSave: "다른 실행에서 저장 데이터가 바뀌었어요. 앱을 다시 열어 최신 기록을 불러온 뒤 시도해 주세요."
        case let .invalidState(reason): "저장 데이터가 올바르지 않아요: \(reason). 원본 파일은 보존했어요."
        }
    }
}
