import Foundation

public enum ActivityPageDirection: Int, Sendable {
    case previous = -1
    case next = 1
}

/// Locks the axis and emits at most one page change per trackpad contact.
/// Momentum belongs to the completed gesture and must never turn another page.
public struct ActivityPagingGesture: Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled, momentum }
    public struct Result: Sendable {
        public let handled: Bool
        public let direction: ActivityPageDirection?
    }
    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var horizontal: Double = 0
    private var vertical: Double = 0
    private var didSwitch = false
    private var tracking = false

    public init() {}

    public mutating func reset() { self = .init() }

    public mutating func update(deltaX: Double, deltaY: Double, phase: Phase) -> Result {
        if phase == .began { reset(); tracking = true }
        if phase == .cancelled {
            let handled = axis == .horizontal
            reset()
            return .init(handled: handled, direction: nil)
        }
        if phase == .momentum || !tracking {
            return .init(handled: axis == .horizontal, direction: nil)
        }
        horizontal += deltaX
        vertical += deltaY
        if axis == nil, max(abs(horizontal), abs(vertical)) >= 8 {
            if abs(horizontal) > abs(vertical) * 1.25 { axis = .horizontal }
            else if abs(vertical) > abs(horizontal) * 1.25 { axis = .vertical }
        }
        var direction: ActivityPageDirection?
        if axis == .horizontal, !didSwitch, abs(horizontal) >= 36 {
            direction = horizontal < 0 ? .next : .previous
            didSwitch = true
        }
        if phase == .ended { tracking = false }
        return .init(handled: axis == .horizontal, direction: direction)
    }
}
