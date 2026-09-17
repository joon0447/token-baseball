import AppKit
import SwiftUI
import TokenBaseballCore

/// A roster portrait prefers the player's photo, with a stable illustrated face otherwise.
struct RosterPlayerPortrait: View {
    let card: PlayerCard
    let size: CGFloat

    var body: some View {
        Group {
            if let image = RosterPortraitAssets.thumbnail(card: card, index: portraitIndex, size: size) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: min(8, size / 4)))
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
        .contentShape(Rectangle())
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

    private static let atlas: CGImage? = bundle.url(forResource: "player-portraits", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    private static var defaultThumbnails: [String: NSImage] = [:]

    static func thumbnail(card: PlayerCard, index: Int, size: CGFloat) -> NSImage? {
        guard size > 0 else { return nil }
        let pixels = max(1, Int(ceil(size * 2)))
        let key = "\(index)-\(size)"
        let source: CGImage
        if let data = card.photoData,
           let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let side = min(image.width, image.height)
            let crop = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
            guard let square = image.cropping(to: crop) else { return nil }
            source = square
        } else {
            if let cached = defaultThumbnails[key] { return cached }
            guard let atlas else { return nil }
            let side = min(atlas.width, atlas.height) / 3
            let crop = CGRect(x: index % 3 * side, y: index / 3 * side, width: side, height: side)
            guard let face = atlas.cropping(to: crop) else { return nil }
            source = face
        }
        // Use a real thumbnail with bounded intrinsic dimensions, never a clipped full-size atlas.
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let bitmap = context.makeImage() else { return nil }
        let thumbnail = NSImage(cgImage: bitmap, size: NSSize(width: size, height: size))
        if card.photoData == nil { defaultThumbnails[key] = thumbnail }
        return thumbnail
    }
}
