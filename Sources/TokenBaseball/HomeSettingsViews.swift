import SwiftUI
import TokenBaseballCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    let navigate: (AppPage) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(title: "내 야구단", subtitle: "AI와 쌓은 기록이 새로운 선수로 이어져요.")
                HStack(spacing: 40) {
                    metric("보유 재화", value: "\(model.state.balance.formatted())볼")
                    metric("인정 토큰", value: model.state.totalTokens.formatted())
                    metric("선수단", value: "\(model.state.lineup.count) / 9")
                }.padding(.vertical, 12)
                Divider()
                if model.state.importFolders.isEmpty {
                    ContentUnavailableView {
                        Label("첫 사용 기록을 연결해 주세요", systemImage: "link")
                    } description: {
                        Text("Codex와 Claude Code의 기록을 반영하면 선수 영입에 쓸 볼을 받을 수 있어요.")
                    } actions: {
                        Button("사용 기록 연결") { navigate(.settings) }.buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("사용 기록", systemImage: "chart.bar") .font(.headline)
                        HStack {
                            Button(action: model.refreshUsage) {
                                Label(model.isImporting ? "반영 중…" : "사용량 반영", systemImage: "arrow.clockwise")
                            }.disabled(model.isImporting)
                            if model.isImporting {
                                ProgressView().controlSize(.small)
                                Button("취소", action: model.cancelImport)
                            }
                            if let date = model.state.lastImport {
                                Text("마지막 반영: \(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let message = model.importMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing: 14) {
                    Button("카드 상점 열기") { navigate(.shop) }
                    Button("선수단 구성하기") { navigate(.roster) }
                }
                GroupBox("구단 기록") {
                    VStack(spacing: 12) {
                        LabeledContent("보유 선수", value: "\(model.state.cards.count)명")
                        LabeledContent("누적 획득 재화", value: "\(model.state.earnedCurrency.formatted())볼")
                        LabeledContent("사용한 재화", value: "\(model.state.spentCurrency.formatted())볼")
                        LabeledContent("다음 1볼까지", value: "\((1_000 - model.state.totalTokens % 1_000).formatted())토큰")
                    }.padding(12)
                }
            }.padding(32).frame(maxWidth: 960, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section {
                Text("Codex와 Claude Code의 로컬 사용 기록을 연결해 주세요. 연결 후 ‘사용량 반영’을 누르면 과거 기록을 포함해 집계합니다.")
                    .foregroundStyle(.secondary)
                sourceRow("Codex", source: "codex", hint: "~/.codex 또는 sessions 폴더")
                sourceRow("Claude Code", source: "claude", hint: "~/.claude 또는 projects 폴더")
            } header: { Text("사용 기록 연결") }
            Section("반영") {
                HStack {
                    Button(action: model.refreshUsage) {
                        Label(model.isImporting ? "사용 기록을 읽고 있어요…" : "사용량 반영", systemImage: "arrow.clockwise")
                    }.disabled(model.isImporting || model.state.importFolders.isEmpty)
                    if model.isImporting {
                        ProgressView().controlSize(.small)
                        Button("취소", action: model.cancelImport)
                    }
                }
                if let message = model.importMessage { Text(message).foregroundStyle(.secondary) }
                Text("기록 식별값과 토큰 수치를 저장합니다. 대화 본문은 앱에 보관하거나 전송하지 않습니다. 이미 반영한 기록에는 재화를 다시 지급하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("초기 운영 규칙") {
                LabeledContent("재화 환산", value: "1,000토큰 = 1볼 · 나머지는 다음 지급에 합산")
                LabeledContent("카드 가격", value: "루키 10볼 / 올스타 30볼 / 레전드 100볼")
                LabeledContent("구매 방식", value: "카드 직접 구매 · 같은 카드 중복 구매 불가")
                Text("개발용 초기값이며 최종 정책이 정해지면 변경될 수 있어요.").font(.caption).foregroundStyle(.secondary)
            }
            Section("데이터 저장") {
                Text(model.saveURL.path).font(.caption).textSelection(.enabled)
                Button("저장 폴더 보기") {
                    NSWorkspace.shared.selectFile(model.saveURL.path, inFileViewerRootedAtPath: model.saveURL.deletingLastPathComponent().path)
                }
            }
        }.formStyle(.grouped).navigationTitle("설정")
    }
    private func sourceRow(_ title: String, source: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(model.state.importFolders[source] ?? hint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("기본 폴더 연결") { model.connectDefault(source: source) }
                Button("폴더 선택…") { model.chooseFolder(source: source) }
                if model.state.importFolders[source] != nil {
                    Label("연결됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                }
            }.disabled(model.isImporting)
        }.padding(.vertical, 6)
    }
}
