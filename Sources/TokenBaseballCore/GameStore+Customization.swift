import Foundation

extension GameStore {
    public func rename(cardID: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30 else { throw GameError.invalidName }
        try updateCard(cardID) { $0.customName = trimmed }
    }

    public func setPhoto(cardID: UUID, data: Data?) throws {
        try updateCard(cardID) { $0.photoData = data }
    }

    public func resetCustomization(cardID: UUID) throws {
        try updateCard(cardID) {
            $0.customName = nil
            $0.photoData = nil
        }
    }

    private func updateCard(_ id: UUID, update: (inout PlayerCard) -> Void) throws {
        guard let index = state.cards.firstIndex(where: { $0.id == id }) else { throw GameError.cardNotFound }
        var candidate = state
        update(&candidate.cards[index])
        try commit(candidate)
    }

}
