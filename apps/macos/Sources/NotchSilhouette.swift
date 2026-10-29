import SwiftUI

/// The top corners flare OUT into the display edge, rather than rounding IN
/// like a floating card. The physical camera remains inside the black center.
struct NotchSilhouette: Shape {
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    var shoulder: CGFloat
    var bottomRadius: CGFloat
    var attached: Bool

    typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    var animatableData: AnimatableData {
        get { .init(.init(bodyWidth, bodyHeight), .init(shoulder, bottomRadius)) }
        set {
            bodyWidth = newValue.first.first
            bodyHeight = newValue.first.second
            shoulder = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = max(1, bodyWidth)
        let height = max(1, bodyHeight)
        let x = rect.midX - width / 2
        if !attached {
            return Path(roundedRect: .init(x: x, y: 0, width: width, height: height),
                        cornerRadius: min(bottomRadius, height / 2))
        }
        let s = min(shoulder, height / 2)
        let r = min(bottomRadius, height - s, width / 2)
        let k: CGFloat = 0.5522847498
        var path = Path()
        path.move(to: .init(x: x - s, y: 0))
        path.addLine(to: .init(x: x + width + s, y: 0))
        path.addCurve(to: .init(x: x + width, y: s),
                      control1: .init(x: x + width + s * (1 - k), y: 0),
                      control2: .init(x: x + width, y: s * (1 - k)))
        path.addLine(to: .init(x: x + width, y: height - r))
        path.addCurve(to: .init(x: x + width - r, y: height),
                      control1: .init(x: x + width, y: height - r * (1 - k)),
                      control2: .init(x: x + width - r * (1 - k), y: height))
        path.addLine(to: .init(x: x + r, y: height))
        path.addCurve(to: .init(x: x, y: height - r),
                      control1: .init(x: x + r * (1 - k), y: height),
                      control2: .init(x: x, y: height - r * (1 - k)))
        path.addLine(to: .init(x: x, y: s))
        path.addCurve(to: .init(x: x - s, y: 0),
                      control1: .init(x: x, y: s * (1 - k)),
                      control2: .init(x: x - s * (1 - k), y: 0))
        path.closeSubpath()
        return path
    }
}
