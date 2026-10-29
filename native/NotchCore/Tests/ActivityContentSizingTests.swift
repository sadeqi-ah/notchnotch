import Foundation
import Testing
@testable import NotchCore

private let timerPage = SurfaceKey(extensionID: "timer", surfaceID: "main")
private let musicPage = SurfaceKey(extensionID: "music", surfaceID: "main")

@Test func rapidReturnRestoresHeightWithoutAnotherLayoutCallback() {
    var sizing = ActivityContentSizing()
    sizing.select(timerPage)
    sizing.measure(240, for: timerPage)
    sizing.select(musicPage)
    sizing.measure(180, for: musicPage)
    // Return before the transition completes: SwiftUI may reuse the original
    // page without calling onAppear or reporting a different intrinsic size.
    for _ in 0..<20 {
        sizing.select(timerPage)
        #expect(sizing.height == 240)
        sizing.select(musicPage)
        #expect(sizing.height == 180)
    }
}

@Test func outgoingPageCannotResizeTheSelectedPage() {
    var sizing = ActivityContentSizing()
    sizing.select(timerPage)
    sizing.measure(240, for: timerPage)
    sizing.select(musicPage)
    sizing.measure(180, for: musicPage)
    let outgoingChangedHeight = sizing.measure(300, for: timerPage)
    #expect(!outgoingChangedHeight)
    #expect(sizing.height == 180)
    // Keep the measurement for the next visit, even if it arrived offscreen.
    sizing.select(timerPage)
    #expect(sizing.height == 300)
}

@Test func firstVisitUsesTheNewMeasurementAndLiveContentStillResizes() {
    var sizing = ActivityContentSizing()
    sizing.select(timerPage)
    sizing.measure(240, for: timerPage)
    sizing.select(musicPage)
    #expect(sizing.height == 240)
    let firstMeasurementChangedHeight = sizing.measure(180.2, for: musicPage)
    #expect(firstMeasurementChangedHeight)
    #expect(sizing.height == 181)
    let liveContentChangedHeight = sizing.measure(220, for: musicPage)
    #expect(liveContentChangedHeight)
    #expect(sizing.height == 220)
    let invalidChangedHeight = sizing.measure(.nan, for: musicPage)
    let negativeChangedHeight = sizing.measure(-1, for: musicPage)
    #expect(!invalidChangedHeight)
    #expect(!negativeChangedHeight)
    #expect(sizing.height == 220)
}

@Test func emptyPageAndNamespacedPagesKeepIndependentHeights() {
    var sizing = ActivityContentSizing()
    sizing.measure(100, for: nil)
    sizing.select(timerPage)
    sizing.measure(240, for: timerPage)
    sizing.select(musicPage)
    sizing.measure(180, for: musicPage)
    sizing.select(nil)
    #expect(sizing.height == 100)
    sizing.select(timerPage)
    #expect(sizing.height == 240)
}
