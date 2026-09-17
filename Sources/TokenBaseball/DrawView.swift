import SwiftUI
import TokenBaseballCore

struct DrawView: View {
    @EnvironmentObject private var model: AppModel
    @State private var revealedID: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(title: "선수 뽑기", subtitle: "\(TokenDisplay.short(DrawPolicy.tokensPerDraw)) 토큰을 사용할 때마다 뽑기 카드 1장이 지급돼요.")
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("보유한 뽑기 카드").foregroundStyle(.secondary)
                        Text("\(model.state.availableDraws.formatted())장").font(.largeTitle.bold()).monospacedDigit()
                    }
                    Spacer()
                    Button("카드 1장 열기") {
                        model.perform { store in revealedID = try store.openDraw() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.state.availableDraws == 0)
                }
                if let id = revealedID, let player = model.card(id) {
                    GroupBox {
                        HStack(spacing: 24) {
                            PlayerPortrait(data: player.photoData, tier: player.tier, size: 130)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("새로운 선수").font(.subheadline).foregroundStyle(.secondary)
                                Text(player.name).font(.largeTitle.bold())
                                TierLabel(tier: player.tier)
                                Label(player.position.title, systemImage: "lock.fill")
                                Text("보유 카드에 추가됐어요.").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(20)
                    }
                } else {
                    ContentUnavailableView {
                        Label("새 선수를 기다리고 있어요", systemImage: "rectangle.stack.fill")
                    } description: {
                        Text(model.state.availableDraws == 0 ? "다음 카드까지 \(TokenDisplay.short(DrawPolicy.tokensPerDraw - model.state.totalTokens % DrawPolicy.tokensPerDraw)) 토큰 남았어요." : "카드를 열면 선수의 등급·이름·포지션이 정해집니다.")
                    }
                }
                Divider()
                Text("루키 75%  ·  올스타 20%  ·  레전드 5%").font(.callout)
                Text("포지션은 9개 중 무작위로 정해지며 변경할 수 없어요. 이름과 사진은 보유 카드에서 바꿀 수 있습니다.")
                    .foregroundStyle(.secondary)
            }.padding(32).frame(maxWidth: 900, alignment: .leading)
        }
    }
}
