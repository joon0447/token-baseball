import SwiftUI
import TokenBaseballCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    let navigate: (AppPage) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(title: "내 야구단", subtitle: "AI와 쌓은 기록으로 새로운 선수를 만나세요.")
                HStack(spacing: 36) {
                    metric("오늘 사용", value: TokenDisplay.short(model.todayTokens), exact: model.todayTokens)
                    metric("누적 토큰", value: TokenDisplay.short(model.state.totalTokens), exact: model.state.totalTokens)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("뽑기 카드").foregroundStyle(.secondary)
                        Text("\(model.state.availableDraws.formatted())장").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    }
                }.padding(.vertical, 12)
                GroupBox("다음 뽑기 카드까지") {
                    VStack(alignment: .leading, spacing: 12) {
                        let remaining = DrawPolicy.tokensPerDraw - model.state.totalTokens % DrawPolicy.tokensPerDraw
                        HStack {
                            Text("\(TokenDisplay.short(remaining)) 토큰 남음").font(.headline)
                            Spacer()
                            Text("\(TokenDisplay.short(DrawPolicy.tokensPerDraw)) 토큰마다 1장").foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(model.state.totalTokens % DrawPolicy.tokensPerDraw), total: Double(DrawPolicy.tokensPerDraw))
                            .accessibilityLabel("다음 뽑기 카드 진행도")
                        Button("선수 뽑기") { navigate(.draw) }.buttonStyle(.borderedProminent)
                    }.padding(12)
                }
                if model.state.importFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("루키 선수 9명이 준비됐어요.").font(.headline)
                        Text("Codex와 Claude Code의 기록을 연결하면 토큰을 집계하고 뽑기 카드를 받을 수 있어요.").foregroundStyle(.secondary)
                        Button("사용 기록 연결") { navigate(.settings) }
                    }
                } else {
                    HStack {
                        Button(action: model.refreshUsage) { Label("사용량 반영", systemImage: "arrow.clockwise") }
                            .disabled(model.isImporting)
                        if model.isImporting { ProgressView().controlSize(.small); Button("취소", action: model.cancelImport) }
                        if let date = model.state.lastImport {
                            Text("마지막 반영: \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let message = model.importMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                Divider()
                HStack {
                    Text("보유 선수 \(model.state.cards.count)명 · 선수단 \(model.state.lineup.count)/9").font(.headline)
                    Spacer()
                    Button("선수단 보기") { navigate(.roster) }
                }
            }.padding(32).frame(maxWidth: 960, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ title: String, value: String, exact: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                .help("\(exact.formatted()) 토큰").accessibilityLabel("\(title) \(exact.formatted()) 토큰")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section("사용 기록 연결") {
                Text("연결된 기록은 앱이 실행 중일 때 1분마다 갱신합니다. 오늘 사용량은 Mac의 날짜 기준이며, 과거 기록은 해당 날짜에 집계합니다.")
                    .foregroundStyle(.secondary)
                sourceRow("Codex", source: "codex", hint: "~/.codex 또는 sessions 폴더")
                sourceRow("Claude Code", source: "claude", hint: "~/.claude 또는 projects 폴더")
            }
            Section("사용량") {
                LabeledContent("오늘 사용한 토큰", value: "\(TokenDisplay.short(model.todayTokens)) (\(model.todayTokens.formatted()))")
                LabeledContent("누적 토큰", value: TokenDisplay.short(model.state.totalTokens))
                HStack {
                    Button(action: model.refreshUsage) { Label("사용량 반영", systemImage: "arrow.clockwise") }
                        .disabled(model.isImporting || model.state.importFolders.isEmpty)
                    if model.isImporting { ProgressView().controlSize(.small); Button("취소", action: model.cancelImport) }
                }
                if let message = model.importMessage { Text(message).foregroundStyle(.secondary) }
                Text("상태바에서도 오늘 사용량을 확인할 수 있어요. 대화 본문은 저장하거나 전송하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("선수와 뽑기 규칙") {
                LabeledContent("기본 선수", value: "포지션별 루키 9명 · 무작위 이름")
                LabeledContent("뽑기 카드", value: "\(TokenDisplay.short(DrawPolicy.tokensPerDraw)) 토큰마다 1장")
                LabeledContent("등급 확률", value: "루키 75% / 올스타 20% / 레전드 5%")
                LabeledContent("선수 포지션", value: "획득 시 무작위 결정 · 변경 불가")
                Text("뽑기는 누적 토큰을 차감하지 않습니다. 선수는 자신의 포지션에만 배치할 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
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
