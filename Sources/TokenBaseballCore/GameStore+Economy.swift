import Foundation

extension GameStore {
    @discardableResult
    public func importUsage(_ snapshots: [UsageSnapshot]) throws -> Int64 {
        var candidate = state
        var added: Int64 = 0
        var batchDaily: [String: [String: Int64]] = [:]
        for snapshot in snapshots {
            guard !snapshot.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  snapshot.totalTokens >= 0 else { throw GameError.invalidUsage }
            var snapshotDailySum: Int64 = 0
            for (day, value) in snapshot.dailyTokens {
                guard GameState.isValidDayKey(day), value >= 0 else { throw GameError.invalidUsage }
                let sum = snapshotDailySum.addingReportingOverflow(value)
                guard !sum.overflow else { throw GameError.arithmeticOverflow }
                snapshotDailySum = sum.partialValue
            }
            guard snapshotDailySum <= snapshot.totalTokens else { throw GameError.invalidUsage }
            if let earlier = batchDaily[snapshot.sourceID], earlier != snapshot.dailyTokens {
                throw GameError.invalidUsage
            }
            batchDaily[snapshot.sourceID] = snapshot.dailyTokens
            let previous = candidate.sourceTotals[snapshot.sourceID] ?? 0
            let next = max(previous, snapshot.totalTokens)
            let delta = next - previous
            let sum = added.addingReportingOverflow(delta)
            guard !sum.overflow else { throw GameError.arithmeticOverflow }
            added = sum.partialValue
            candidate.sourceTotals[snapshot.sourceID] = next
            // A complete source read is authoritative for dates. This permits
            // corrected timestamps or timezone changes without crediting tokens again.
            if snapshot.dailyTokens.isEmpty {
                candidate.sourceDailyTotals.removeValue(forKey: snapshot.sourceID)
            } else {
                candidate.sourceDailyTotals[snapshot.sourceID] = snapshot.dailyTokens
            }
        }
        let total = candidate.totalTokens.addingReportingOverflow(added)
        guard !total.overflow else { throw GameError.arithmeticOverflow }
        candidate.totalTokens = total.partialValue
        candidate.lastImport = Date()
        try commit(candidate)
        return added
    }

    @discardableResult
    public func openDraw() throws -> UUID {
        guard state.availableDraws > 0 else { throw GameError.noDrawsAvailable }
        let roll = PlayerGenerator.index(randomIndex, count: 100)
        let tier: CardTier = roll < DrawPolicy.rookieWeight ? .rookie
            : roll < DrawPolicy.rookieWeight + DrawPolicy.allStarWeight ? .allStar : .legend
        let position = FieldPosition.allCases[PlayerGenerator.index(randomIndex, count: FieldPosition.allCases.count)]
        let card = PlayerGenerator.make(tier: tier, position: position, randomIndex: randomIndex)
        var candidate = state
        candidate.openedDraws += 1 // Bounded above by totalTokens / tokensPerDraw.
        candidate.cards.append(card)
        try commit(candidate)
        return card.id
    }
}
