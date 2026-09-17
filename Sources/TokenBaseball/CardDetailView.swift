import AppKit
import ImageIO
import SwiftUI
import TokenBaseballCore
import UniformTypeIdentifiers

struct CardDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let initialCard: PlayerCard
    @State private var editedName: String
    @State private var pendingPhoto: Data?
    @State private var localMessage: String?

    init(initialCard: PlayerCard) {
        self.initialCard = initialCard
        _editedName = State(initialValue: initialCard.name)
    }
    private var card: PlayerCard { model.card(initialCard.id) ?? initialCard }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("선수 카드").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 20) {
                PlayerPortrait(data: pendingPhoto ?? card.photoData, tier: card.tier, size: 130)
                VStack(alignment: .leading, spacing: 10) {
                    Text(card.name).font(.title.bold())
                    TierLabel(tier: card.tier)
                    Text(card.position.title).foregroundStyle(.secondary)
                    if let current = model.assignedPosition(card.id) {
                        Text("\(current.title)에 배치 중").font(.caption)
                    }
                }
            }
            Divider()
            Form {
                TextField("선수 이름", text: $editedName)
                HStack {
                    Text("앞뒤 공백 제외 1~30자").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("이름 저장") {
                        localMessage = nil
                        if model.perform({ try $0.rename(cardID: card.id, name: editedName) }) {
                            editedName = card.name
                            localMessage = "이름을 저장했어요."
                        }
                    }
                }
                Divider().padding(.vertical, 6)
                HStack {
                    Button("사진 선택…", action: choosePhoto)
                    Text("PNG · JPEG, 최대 10MB").font(.caption).foregroundStyle(.secondary)
                }
                if let pendingPhoto {
                    HStack {
                        Text("위 미리보기로 표시됩니다.").font(.caption)
                        Spacer()
                        Button("취소") { self.pendingPhoto = nil }
                        Button("사진 적용") {
                            localMessage = nil
                            if model.perform({ try $0.setPhoto(cardID: card.id, data: pendingPhoto) }) {
                                self.pendingPhoto = nil
                                localMessage = "사진을 적용했어요."
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Button("이름·사진 기본값 복원") {
                    localMessage = nil
                    if model.perform({ try $0.resetCustomization(cardID: card.id) }) {
                        editedName = card.name
                        pendingPhoto = nil
                        localMessage = "기본 이름과 사진으로 복원했어요."
                    }
                }
                Divider().padding(.vertical, 6)
                LabeledContent("고정 포지션") { Label(card.position.title, systemImage: "lock.fill") }
                HStack {
                    Text("같은 포지션의 기존 선수와 교체됩니다.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("\(card.position.title)에 배치") {
                        localMessage = nil
                        if model.perform({ try $0.assign(cardID: card.id, to: card.position) }) {
                            localMessage = "\(card.position.title)에 배치했어요."
                        }
                    }
                }
            }
            if let localMessage { Text(localMessage).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(28).frame(width: 530)
        .onChange(of: model.errorMessage) { _, message in
            if let message {
                localMessage = message
                model.errorMessage = nil
            }
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "미리보기"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let metadata = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let count = metadata.fileSize, count > 0, count <= 10 * 1_024 * 1_024 else {
                throw PhotoError.invalidSize
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) as String?,
                  [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_024
                  ] as CFDictionary),
                  let png = NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:]) else {
                throw PhotoError.invalidImage
            }
            pendingPhoto = png
            localMessage = nil
        } catch { localMessage = error.localizedDescription }
    }
}

private enum PhotoError: LocalizedError {
    case invalidSize, invalidImage
    var errorDescription: String? {
        switch self {
        case .invalidSize: "사진은 10MB 이하의 파일을 선택해 주세요."
        case .invalidImage: "사진을 읽을 수 없어요. 유효한 PNG 또는 JPEG 파일을 선택해 주세요."
        }
    }
}
