import Foundation

/// The selected page owns the shell height, including when an interrupted
/// transition reuses a page without another appearance or size-change callback.
public struct ActivityContentSizing: Sendable {
    public private(set) var height: CGFloat = 156
    private var selection: SurfaceKey?
    private var measurements: [SurfaceKey?: CGFloat] = [:]

    public init() {}

    @discardableResult
    public mutating func select(_ key: SurfaceKey?) -> Bool {
        selection = key
        guard let measured = measurements[key] else { return false }
        return setHeight(measured)
    }

    @discardableResult
    public mutating func measure(_ height: CGFloat, for key: SurfaceKey?) -> Bool {
        guard height.isFinite, height >= 0 else { return false }
        let measured = ceil(height)
        measurements[key] = measured
        guard key == selection else { return false }
        return setHeight(measured)
    }

    private mutating func setHeight(_ height: CGFloat) -> Bool {
        guard self.height != height else { return false }
        self.height = height
        return true
    }
}
