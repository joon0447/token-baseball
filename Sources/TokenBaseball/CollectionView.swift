import SwiftUI
import TokenBaseballCore

struct CollectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tier: CardTier?
    @State private var selectedCard: PlayerCard?
    let navigate: (AppPage) -> Void
    private var cards: [PlayerCard] { model.state.cards.filter { tier == nil || $0.tier == tier } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "보유 카드", subtitle: "\(model.state.cards.count)명의 선수 · 카드를 선택해 이름과 사진을 바꿔 보세요.")
                .padding([.top, .horizontal], 32)
            TierFilter(selection: $tier).padding(.horizontal, 32)
            if cards.isEmpty {
                ContentUnavailableView {
                    Label(model.state.cards.isEmpty ? "아직 보유한 선수가 없어요" : "이 등급의 카드가 없어요", systemImage: "rectangle.stack")
                } description: {
                    Text(model.state.cards.isEmpty ? "토큰을 사용해 뽑기 카드를 받아 보세요." : "다른 등급을 선택하거나 선수 뽑기를 확인해 보세요.")
                } actions: {
                    Button("선수 뽑기") { navigate(.draw) }
                }
            } else {
                List(cards) { card in
                    Button { selectedCard = card } label: {
                        HStack(spacing: 16) {
                            PlayerPortrait(data: card.photoData, tier: card.tier, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.name).font(.headline).foregroundStyle(.primary)
                                HStack { TierLabel(tier: card.tier); Text(card.position.title).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if let position = model.assignedPosition(card.id) {
                                Text("\(position.title) 배치 중").font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(card.name) 카드 상세")
                }.listStyle(.inset)
            }
        }
        .sheet(item: $selectedCard) { CardDetailView(initialCard: $0) }
    }
}
