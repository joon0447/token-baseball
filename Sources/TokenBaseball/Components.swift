import AppKit
import SwiftUI
import TokenBaseballCore

extension CardTier {
    var color: Color {
        switch self { case .rookie: .blue; case .allStar: .purple; case .legend: .orange }
    }
}

struct PlayerPortrait: View {
    let data: Data?
    let tier: CardTier
    var size: CGFloat = 80
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    tier.color.opacity(0.10)
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: size * 0.55)).foregroundStyle(tier.color)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

struct TierLabel: View {
    let tier: CardTier
    var body: some View {
        Text(tier.title).font(.caption.weight(.semibold)).foregroundStyle(tier.color)
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TierFilter: View {
    @Binding var selection: CardTier?
    var body: some View {
        Picker("등급", selection: $selection) {
            Text("전체").tag(nil as CardTier?)
            ForEach(CardTier.allCases) { tier in Text(tier.title).tag(tier as CardTier?) }
        }.pickerStyle(.segmented).frame(maxWidth: 360)
    }
}
