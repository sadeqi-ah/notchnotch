import Foundation
import Testing
@testable import NotchCore

private let start = Date(timeIntervalSince1970: 1_000)

@Test func shortHoverHighlightsImmediatelyAndLongHoverOpensAfterDwell() {
    var hover = HoverState()
    hover.pointerChanged(inside: true, now: start)
    #expect(hover.isHighlighted)
    #expect(!hover.isExpanded)
    hover.advance(now: start.addingTimeInterval(HoverState.dwell - 0.001))
    #expect(!hover.isExpanded)
    hover.advance(now: start.addingTimeInterval(HoverState.dwell))
    #expect(hover.isExpanded)
}

@Test func leavingBeforeDwellCancelsOpeningAndHidesAfterTheExitGrace() {
    var hover = HoverState()
    hover.pointerChanged(inside: true, now: start)
    hover.pointerChanged(inside: false, now: start.addingTimeInterval(0.2))
    hover.advance(now: start.addingTimeInterval(0.3))
    #expect(hover.isHighlighted)
    #expect(!hover.isExpanded)
    hover.advance(now: start.addingTimeInterval(1))
    #expect(!hover.isHighlighted)
    #expect(!hover.isExpanded)
}

@Test func returningDuringTheExitGraceKeepsThePanelOpen() {
    var hover = HoverState()
    hover.pointerChanged(inside: true, now: start)
    hover.advance(now: start.addingTimeInterval(1))
    hover.pointerChanged(inside: false, now: start.addingTimeInterval(2))
    hover.pointerChanged(inside: true, now: start.addingTimeInterval(2.1))
    hover.advance(now: start.addingTimeInterval(3))
    #expect(hover.isExpanded)
    #expect(hover.isHighlighted)
}

@Test func newEntryMustDwellAgainAndResetCancelsAllHoverState() {
    var hover = HoverState()
    hover.pointerChanged(inside: true, now: start)
    hover.pointerChanged(inside: false, now: start.addingTimeInterval(0.4))
    hover.pointerChanged(inside: true, now: start.addingTimeInterval(0.5))
    hover.advance(now: start.addingTimeInterval(1))
    #expect(!hover.isExpanded)
    hover.reset()
    hover.advance(now: start.addingTimeInterval(10))
    #expect(!hover.isHighlighted)
    #expect(!hover.isExpanded)
    #expect(hover.deadline == nil)
}
