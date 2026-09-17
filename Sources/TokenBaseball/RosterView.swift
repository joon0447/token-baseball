import SwiftUI
import TokenBaseballCore

struct RosterView: View {
    @EnvironmentObject private var model: AppModel
    let navigate: (AppPage) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "내 선수단", subtitle: "9개 수비 포지션 중 \(model.state.lineup.count)자리를 채웠어요.")
                if model.state.cards.isEmpty {
                    HStack {
                        Text("카드 상점에서 선수를 영입하면 여기에 배치할 수 있어요.").foregroundStyle(.secondary)
                        Spacer()
                        Button("카드 상점 열기") { navigate(.shop) }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(FieldPosition.allCases) { position in
                        rosterRow(position).padding(.vertical, 14)
                        if position != FieldPosition.allCases.last { Divider() }
                    }
                }
                Text("교체하거나 제외한 선수는 보유 카드에 남습니다. 같은 카드 한 장은 한 자리에만 배치할 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
    private func rosterRow(_ position: FieldPosition) -> some View {
        let id = model.state.lineup[position.rawValue]
        let card = id.flatMap { model.card($0) }
        let available = model.state.cards.filter { model.assignedPosition($0.id) == nil || $0.id == id }
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(position.abbreviation).font(.headline).monospaced()
                Text(position.title).font(.caption).foregroundStyle(.secondary)
            }.frame(width: 64, alignment: .leading)
            if let card {
                PlayerPortrait(data: card.photoData, tier: card.tier, size: 44)
                Text(card.name).font(.headline)
                TierLabel(tier: card.tier)
            } else {
                Text("빈자리").foregroundStyle(.secondary)
            }
            Spacer()
            Menu(card == nil ? "선수 등록" : "선수 교체") {
                ForEach(available) { candidate in
                    Button("\(candidate.name) · \(candidate.tier.title)") {
                        model.perform { try $0.assign(cardID: candidate.id, to: position) }
                    }
                }
            }.frame(width: 108).disabled(available.isEmpty)
                .accessibilityLabel("\(position.title) \(card == nil ? "선수 등록" : "선수 교체")")
            Button("제외") { model.perform { try $0.remove(from: position) } }
                .disabled(card == nil).accessibilityLabel("\(position.title) 선수 제외")
        }
    }
}
