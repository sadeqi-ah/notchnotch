import Testing
@testable import NotchCore

@Test func horizontalSwipeAccumulatesAndSwitchesOnlyOnce() {
    var gesture = ActivityPagingGesture()
    #expect(gesture.update(deltaX: -12, deltaY: 1, phase: .began).direction == nil)
    let result = gesture.update(deltaX: -25, deltaY: 2, phase: .changed)
    #expect(result.handled)
    #expect(result.direction == .next)
    #expect(gesture.update(deltaX: -150, deltaY: 0, phase: .changed).direction == nil)
    #expect(gesture.update(deltaX: -50, deltaY: 0, phase: .ended).direction == nil)
    let momentum = gesture.update(deltaX: -200, deltaY: 0, phase: .momentum)
    #expect(momentum.handled)
    #expect(momentum.direction == nil)
}

@Test func freshContactCanSwitchInTheOppositeDirection() {
    var gesture = ActivityPagingGesture()
    #expect(gesture.update(deltaX: -40, deltaY: 0, phase: .began).direction == .next)
    _ = gesture.update(deltaX: 0, deltaY: 0, phase: .ended)
    _ = gesture.update(deltaX: -40, deltaY: 0, phase: .momentum)
    #expect(gesture.update(deltaX: 40, deltaY: 0, phase: .began).direction == .previous)
}

@Test func verticalScrollStaysVerticalEvenIfTheFingersDriftSideways() {
    var gesture = ActivityPagingGesture()
    let vertical = gesture.update(deltaX: 1, deltaY: 12, phase: .began)
    #expect(!vertical.handled)
    let drift = gesture.update(deltaX: -100, deltaY: 10, phase: .changed)
    #expect(!drift.handled)
    #expect(drift.direction == nil)
}

@Test func diagonalJitterAndShortSwipesDoNotTurnPages() {
    var gesture = ActivityPagingGesture()
    #expect(!gesture.update(deltaX: -5, deltaY: 5, phase: .began).handled)
    #expect(!gesture.update(deltaX: -20, deltaY: 20, phase: .changed).handled)
    #expect(gesture.update(deltaX: 0, deltaY: 0, phase: .ended).direction == nil)
    #expect(gesture.update(deltaX: -20, deltaY: 0, phase: .began).direction == nil)
    #expect(gesture.update(deltaX: 0, deltaY: 0, phase: .ended).direction == nil)
    #expect(gesture.update(deltaX: -100, deltaY: 0, phase: .momentum).direction == nil)
}

@Test func cancellationAndLeavingThePanelDiscardPartialGestures() {
    var gesture = ActivityPagingGesture()
    _ = gesture.update(deltaX: -20, deltaY: 0, phase: .began)
    #expect(gesture.update(deltaX: -30, deltaY: 0, phase: .cancelled).direction == nil)
    #expect(!gesture.update(deltaX: -100, deltaY: 0, phase: .momentum).handled)
    _ = gesture.update(deltaX: -20, deltaY: 0, phase: .began)
    gesture.reset()
    #expect(gesture.update(deltaX: -100, deltaY: 0, phase: .changed).direction == nil)
    #expect(gesture.update(deltaX: -20, deltaY: 0, phase: .began).direction == nil)
}
