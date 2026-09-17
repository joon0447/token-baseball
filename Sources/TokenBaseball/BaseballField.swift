import SwiftUI
import TokenBaseballCore

/// The live field and layout previews use the same positions and slot sizing.
struct BaseballField<Slot: View>: View {
    private let slot: (FieldPosition, CGFloat) -> Slot

    init(@ViewBuilder slot: @escaping (FieldPosition, CGFloat) -> Slot) {
        self.slot = slot
    }

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = max(0, min(88, geometry.size.width * 0.17))
            let portraitSize = max(0, min(48, slotWidth - 8))
            ZStack {
                BaseballGrass().fill(Color.green.opacity(0.12))
                BaseballDiamond().fill(Color.brown.opacity(0.12))
                BaseballDiamond().stroke(Color.primary.opacity(0.24), lineWidth: 2)
                ForEach(FieldPosition.allCases) { position in
                    let point = fieldPoint(position)
                    slot(position, portraitSize)
                        .frame(width: slotWidth, height: 96)
                        .position(x: geometry.size.width * point.x, y: geometry.size.height * point.y)
                }
            }
        }
        .frame(height: 520)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    /// View from home: outfield behind the diamond, infield around the bases, catcher behind home.
    private func fieldPoint(_ position: FieldPosition) -> CGPoint {
        switch position {
        case .leftField: CGPoint(x: 0.20, y: 0.26)
        case .centerField: CGPoint(x: 0.50, y: 0.14)
        case .rightField: CGPoint(x: 0.80, y: 0.26)
        case .shortstop: CGPoint(x: 0.38, y: 0.42)
        case .secondBase: CGPoint(x: 0.62, y: 0.42)
        case .thirdBase: CGPoint(x: 0.25, y: 0.64)
        case .firstBase: CGPoint(x: 0.75, y: 0.64)
        case .pitcher: CGPoint(x: 0.50, y: 0.63)
        case .catcher: CGPoint(x: 0.50, y: 0.90)
        }
    }
}

private struct BaseballGrass: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.width * 0.02, y: rect.height * 0.30))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.98, y: rect.height * 0.30),
                          control: CGPoint(x: rect.width * 0.50, y: -rect.height * 0.22))
        path.closeSubpath()
        return path
    }
}

private struct BaseballDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.58))
        path.closeSubpath()
        return path
    }
}
