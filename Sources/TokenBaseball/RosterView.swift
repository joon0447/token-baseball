import SwiftUI
import TokenBaseballCore

struct RosterView: View {
    @EnvironmentObject private var model: AppModel
    let navigate: (AppPage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "내 선수단", subtitle: "9개 수비 포지션 중 \(model.state.lineup.count)자리를 채웠어요.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("수비 배치").font(.title2.bold())
                    Text("포지션 카드를 눌러 같은 포지션의 선수로 교체할 수 있어요.")
                        .foregroundStyle(.secondary)
                    defensiveField
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("포지션별 선수 목록").font(.title2.bold()).padding(.bottom, 8)
                    ForEach(FieldPosition.allCases) { position in
                        rosterRow(position).padding(.vertical, 14)
                        if position != FieldPosition.allCases.last { Divider() }
                    }
                }
                Text("선수의 포지션은 고정되어 있어요. 교체하거나 제외한 선수는 보유 카드에 남습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
    }

    private var defensiveField: some View {
        GeometryReader { geometry in
            ZStack {
                BaseballGrass().fill(Color.green.opacity(0.12))
                BaseballDiamond().fill(Color.brown.opacity(0.12))
                BaseballDiamond().stroke(Color.primary.opacity(0.24), lineWidth: 2)
                ForEach(FieldPosition.allCases) { position in
                    let point = fieldPoint(position)
                    fieldSlot(position, portraitSize: max(0, min(84, geometry.size.width * 0.185 - 12)))
                        .frame(width: min(128, geometry.size.width * 0.185), height: 140)
                        .position(x: geometry.size.width * point.x, y: geometry.size.height * point.y)
                }
            }
        }
        .frame(height: 640)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }

    private func fieldSlot(_ position: FieldPosition, portraitSize: CGFloat) -> some View {
        let card = model.state.lineup[position.rawValue].flatMap { model.card($0) }
        let available = availableCards(for: position, currentID: card?.id)
        return Menu {
            if available.isEmpty {
                Text("교체할 \(position.title) 카드가 없어요")
            } else {
                ForEach(available) { candidate in
                    Button("\(candidate.name) · \(candidate.tier.title)") {
                        model.perform { try $0.assign(cardID: candidate.id, to: position) }
                    }
                }
            }
            if card != nil {
                Divider()
                Button("선수단에서 제외") { model.perform { try $0.remove(from: position) } }
            }
        } label: {
            RosterFieldCard(card: card, position: position, portraitSize: portraitSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(card == nil && available.isEmpty)
        .accessibilityLabel("\(position.title), \(card.map { "\($0.name), \($0.tier.title)" } ?? "빈자리"), \(card == nil ? "선수 등록" : "선수 교체 또는 제외")")
        .help("\(position.title) 선수를 선택하세요. 선수의 포지션은 변경할 수 없어요.")
    }

    private func rosterRow(_ position: FieldPosition) -> some View {
        let id = model.state.lineup[position.rawValue]
        let card = id.flatMap { model.card($0) }
        let available = availableCards(for: position, currentID: id)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(position.abbreviation).font(.headline).monospaced()
                Text(position.title).font(.caption).foregroundStyle(.secondary)
            }.frame(width: 64, alignment: .leading)
            if let card {
                RosterPlayerPortrait(card: card, size: 44)
                Text(card.name).font(.headline).lineLimit(1)
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

    private func availableCards(for position: FieldPosition, currentID: UUID?) -> [PlayerCard] {
        model.state.cards.filter {
            $0.position == position && $0.id != currentID && model.assignedPosition($0.id) == nil
        }
    }

    /// Coordinates follow the defense as seen from home plate; the catcher sits behind home.
    private func fieldPoint(_ position: FieldPosition) -> CGPoint {
        switch position {
        case .leftField: CGPoint(x: 0.15, y: 0.16)
        case .centerField: CGPoint(x: 0.50, y: 0.12)
        case .rightField: CGPoint(x: 0.85, y: 0.16)
        case .shortstop: CGPoint(x: 0.34, y: 0.36)
        case .secondBase: CGPoint(x: 0.66, y: 0.36)
        case .thirdBase: CGPoint(x: 0.15, y: 0.59)
        case .firstBase: CGPoint(x: 0.85, y: 0.59)
        case .pitcher: CGPoint(x: 0.50, y: 0.59)
        case .catcher: CGPoint(x: 0.50, y: 0.87)
        }
    }
}

private struct BaseballGrass: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.81))
        path.addLine(to: CGPoint(x: rect.width * 0.02, y: rect.height * 0.28))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.98, y: rect.height * 0.28),
                          control: CGPoint(x: rect.width * 0.50, y: -rect.height * 0.20))
        path.closeSubpath()
        return path
    }
}

private struct BaseballDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.81))
        path.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.25))
        path.addLine(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.53))
        path.closeSubpath()
        return path
    }
}
