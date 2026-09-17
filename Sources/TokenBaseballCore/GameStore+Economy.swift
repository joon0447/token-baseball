import Foundation

extension GameStore {
    @discardableResult
    public func importUsage(_ snapshots: [UsageSnapshot]) throws -> Int64 {
        var candidate = state
        var added: Int64 = 0
        for snapshot in snapshots {
            guard !snapshot.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  snapshot.totalTokens >= 0 else { throw GameError.invalidUsage }
            let previous = candidate.sourceTotals[snapshot.sourceID] ?? 0
            let next = max(previous, snapshot.totalTokens)
            let delta = next - previous
            let sum = added.addingReportingOverflow(delta)
            guard !sum.overflow else { throw GameError.arithmeticOverflow }
            added = sum.partialValue
            candidate.sourceTotals[snapshot.sourceID] = next
        }
        let total = candidate.totalTokens.addingReportingOverflow(added)
        guard !total.overflow else { throw GameError.arithmeticOverflow }
        candidate.totalTokens = total.partialValue
        candidate.earnedCurrency = candidate.totalTokens / GameState.tokensPerCurrency
        candidate.lastImport = Date()
        try commit(candidate)
        return added
    }

    @discardableResult
    public func purchase(offerID: String) throws -> UUID {
        guard let offer = Catalog.offers.first(where: { $0.id == offerID }) else { throw GameError.unknownOffer }
        guard !state.cards.contains(where: { $0.catalogID == offerID }) else { throw GameError.alreadyOwned }
        guard state.balance >= offer.price else {
            throw GameError.insufficientFunds(required: offer.price, available: state.balance)
        }
        var candidate = state
        let spent = candidate.spentCurrency.addingReportingOverflow(offer.price)
        guard !spent.overflow else { throw GameError.arithmeticOverflow }
        candidate.spentCurrency = spent.partialValue
        let card = PlayerCard(catalogID: offer.id, defaultName: offer.name, tier: offer.tier, position: offer.position)
        candidate.cards.append(card)
        try commit(candidate)
        return card.id
    }

}
