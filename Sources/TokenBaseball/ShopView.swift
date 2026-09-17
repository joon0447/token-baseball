import SwiftUI
import TokenBaseballCore

struct ShopView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tier: CardTier?
    @State private var pendingPurchase: CardOffer?
    @State private var successMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "카드 상점", subtitle: "함께할 선수를 골라 영입하세요. 보유 재화 \(model.state.balance.formatted())볼")
                TierFilter(selection: $tier)
                if let successMessage { Label(successMessage, systemImage: "checkmark.circle").foregroundStyle(.green) }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Catalog.offers.filter { tier == nil || $0.tier == tier }) { offer in
                        offerView(offer)
                    }
                }
            }.padding(32)
        }
        .alert("선수를 영입할까요?", isPresented: Binding(get: { pendingPurchase != nil }, set: { if !$0 { pendingPurchase = nil } })) {
            Button("취소", role: .cancel) { pendingPurchase = nil }
            Button("영입") {
                if let offer = pendingPurchase, model.perform({ _ = try $0.purchase(offerID: offer.id) }) {
                    successMessage = "\(offer.name) 선수를 영입했어요. 보유 카드에서 확인하세요."
                }
                pendingPurchase = nil
            }
        } message: {
            if let offer = pendingPurchase { Text("\(offer.name) · \(offer.tier.title)\n\(offer.price)볼을 사용합니다.") }
        }
    }

    private func offerView(_ offer: CardOffer) -> some View {
        let owned = model.state.cards.contains { $0.catalogID == offer.id }
        let shortage = max(0, offer.price - model.state.balance)
        return VStack(alignment: .leading, spacing: 12) {
            HStack { TierLabel(tier: offer.tier); Spacer(); Text(offer.position.abbreviation).font(.caption).foregroundStyle(.secondary) }
            PlayerPortrait(data: nil, tier: offer.tier, size: 88).frame(maxWidth: .infinity)
            Text(offer.name).font(.title3.bold())
            Text(offer.position.title).foregroundStyle(.secondary)
            HStack {
                Text("\(offer.price)볼").monospacedDigit().font(.headline)
                Spacer()
                Button(owned ? "보유 중" : "영입") { pendingPurchase = offer }
                    .disabled(owned || shortage > 0 || pendingPurchase != nil)
                    .accessibilityLabel("\(offer.name) \(owned ? "보유 중" : "영입")")
            }
            Text(owned ? "보유 카드에서 확인할 수 있어요" : shortage > 0 ? "\(shortage.formatted())볼 더 필요해요" : "바로 영입할 수 있어요")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
