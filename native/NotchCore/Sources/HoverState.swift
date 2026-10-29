import Foundation

/// Immediate hover feedback, then a deliberate dwell before showing full controls.
/// Dates are injected so interrupted entry/exit can be checked without real sleeps.
public struct HoverState: Sendable {
    public static let dwell: TimeInterval = 0.85
    public static let exitDelay: TimeInterval = 0.18
    public private(set) var isHighlighted = false
    public private(set) var isExpanded = false
    public private(set) var deadline: Date?
    private var inside = false

    public init() {}

    public mutating func pointerChanged(inside: Bool, now: Date = .now) {
        guard self.inside != inside else { return }
        self.inside = inside
        if inside {
            isHighlighted = true
            deadline = isExpanded ? nil : now.addingTimeInterval(Self.dwell)
        } else {
            deadline = now.addingTimeInterval(Self.exitDelay)
        }
    }

    public mutating func advance(now: Date = .now) {
        guard let deadline, now >= deadline else { return }
        self.deadline = nil
        isExpanded = inside
        isHighlighted = inside
    }

    public mutating func reset() { self = .init() }
}
