import AppKit
import SwiftUI
import TokenBaseballCore

/// A roster portrait prefers the player's photo, with a stable illustrated face otherwise.
struct RosterPlayerPortrait: View {
    let card: PlayerCard
    let size: CGFloat

    var body: some View {
        Group {
            if let data = card.photoData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let image = RosterPortraitAssets.image {
                Image(nsImage: image)
                    .resizable().interpolation(.high)
                    .frame(width: size * 3, height: size * 3)
                    .offset(x: -CGFloat(portraitIndex % 3) * size,
                            y: -CGFloat(portraitIndex / 3) * size)
                    .frame(width: size, height: size, alignment: .topLeading)
                    .clipped()
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var portraitIndex: Int {
        if card.origin == .starter {
            return FieldPosition.allCases.firstIndex(of: card.position) ?? 0
        }
        // Do not use Swift's randomized hashValue: a face must survive relaunches and renames.
        return card.id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % 9 }
    }
}

/// Kept as a view so the menu label and rendered layout share the same hierarchy.
struct RosterFieldCard: View {
    let card: PlayerCard?
    let position: FieldPosition
    let portraitSize: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            if let card {
                RosterPlayerPortrait(card: card, size: portraitSize)
                Text(card.name).font(.caption.weight(.semibold)).lineLimit(1)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(width: portraitSize, height: portraitSize)
                    .overlay { Text("빈자리").font(.caption).foregroundStyle(.secondary) }
                Text("선수 등록").font(.caption.weight(.semibold))
            }
            Text("\(position.abbreviation) · \(position.title)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.16)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
private enum RosterPortraitAssets {
    static let bundle: Bundle = {
        // SwiftPM's generated accessor does not look inside a macOS app's Resources directory.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TokenBaseball_TokenBaseball.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()

    static let image: NSImage? = bundle.url(forResource: "player-portraits", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
}
