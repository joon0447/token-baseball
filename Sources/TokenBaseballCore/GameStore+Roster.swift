import Foundation

extension GameStore {
    public func assign(cardID: UUID, to position: FieldPosition) throws {
        guard let card = state.cards.first(where: { $0.id == cardID }) else { throw GameError.cardNotFound }
        guard card.position == position else { throw GameError.positionMismatch }
        guard !state.lineup.contains(where: { $0.key != position.rawValue && $0.value == cardID }) else {
            throw GameError.cardAlreadyAssigned
        }
        var candidate = state
        candidate.lineup[position.rawValue] = cardID
        try commit(candidate)
    }

    public func remove(from position: FieldPosition) throws {
        var candidate = state
        candidate.lineup.removeValue(forKey: position.rawValue)
        try commit(candidate)
    }

}
