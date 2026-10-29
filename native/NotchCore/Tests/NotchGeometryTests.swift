import Foundation
import CoreGraphics
import Testing
@testable import NotchCore

@Test func notchUsesTheSameTopCenterAnchorThroughoutExpansion() {
    let geometry = NotchGeometry(cameraWidth: 184, cameraHeight: 32)
    let compact = geometry.bodyFrame(expanded: false)
    let expanded = geometry.bodyFrame(expanded: true)
    #expect(compact.minY == 0)
    #expect(expanded.minY == 0)
    #expect(compact.midX == expanded.midX)
    #expect(compact.width == 244)
    #expect(expanded.width == 384)
}

@Test func tallContentIsNeverCappedOrClippedByTheAnimationWindow() {
    let short = NotchGeometry(contentHeight: 120)
    let tall = NotchGeometry(contentHeight: 4000)
    #expect(tall.fittedContentHeight == 4000)
    #expect(tall.expandedHeight - short.expandedHeight == 3880)
    #expect(tall.canvasSize.height > short.canvasSize.height)
    #expect(tall.expandedHeight + 28 <= tall.canvasSize.height)
    #expect(tall.expandedWidth + 2 * tall.shoulderRadius(expanded: true) < tall.canvasSize.width)
}

@Test func shorterContentKeepsReservedSpaceUntilTheClosingSpringFinishes() {
    let tall = NotchGeometry(contentHeight: 900)
    let short = NotchGeometry(contentHeight: 120, reservedCanvasHeight: tall.canvasSize.height)
    #expect(short.fittedContentHeight == 120)
    #expect(short.expandedHeight < tall.expandedHeight)
    #expect(short.canvasSize == tall.canvasSize)
    #expect(short.bodyFrame(expanded: false).minY == short.bodyFrame(expanded: true).minY)
}

@Test func fittingRoundsUpSubpixelContentWithoutAddingAnArbitraryMinimum() {
    let geometry = NotchGeometry(contentHeight: 42.25)
    #expect(geometry.fittedContentHeight == 43)
    #expect(geometry.expandedHeight == geometry.cameraHeight + 8 + 43 + 14)
}

@Test func physicalCameraFitsInBothStatesAndFloatingDisplaysHaveNoShoulders() {
    let geometry = NotchGeometry(cameraWidth: 220, cameraHeight: 38)
    #expect(geometry.bodySize(expanded: false).width >= 220)
    #expect(geometry.bodySize(expanded: false).height == 38)
    #expect(geometry.expandedWidth >= geometry.compactWidth)
    let floating = NotchGeometry(cameraWidth: 54, attached: false)
    #expect(floating.shoulderRadius(expanded: true) == 0)
    #expect(floating.shoulderRadius(expanded: false) == 0)
}

@Test func peekReservesTheCameraAndAddsOnlyAShortLowerRow() {
    for attached in [true, false] {
        let geometry = NotchGeometry(cameraWidth: 220, cameraHeight: 38, attached: attached)
        let compact = geometry.bodySize(presentation: .compact)
        let peek = geometry.bodySize(presentation: .peek)
        let expanded = geometry.bodySize(presentation: .expanded)
        #expect(compact.width < peek.width)
        #expect(peek.width < expanded.width)
        #expect(peek.height == compact.height + 46)
        #expect(peek.height < expanded.height)
        #expect(peek.width >= geometry.cameraWidth + 60)
        #expect(peek.height + 28 <= geometry.canvasSize.height)
        #expect(geometry.shoulderRadius(presentation: .peek) == (attached ? 18 : 0))
        #expect(geometry.bottomRadius(presentation: .peek) == 22)
    }
}

@Test func idleHidesAtTheCameraAndHoverHasASmallDiscoverableLip() {
    let geometry = NotchGeometry(cameraWidth: 184, cameraHeight: 32, hasActivity: false)
    let idle = geometry.bodyFrame(presentation: .idle)
    let hover = geometry.bodyFrame(presentation: .hovered)
    #expect(idle.width == 184)
    #expect(idle.height == 32)
    #expect(hover.width == 256)
    #expect(hover.height == 42)
    #expect(idle.midX == hover.midX)
    #expect(idle.minY == hover.minY)
    #expect(geometry.activationFrame(presentation: .idle).maxY == 38)
}

@Test func activeHoverIsOnlyASmallStepAndTheMusicLayoutNeedsNoExtraHeader() {
    let geometry = NotchGeometry(cameraWidth: 184, cameraHeight: 32)
    #expect(geometry.hoveredWidth == geometry.compactWidth + 12)
    #expect(geometry.hoveredHeight == geometry.cameraHeight + 4)
    let music = NotchGeometry(contentHeight: 172, expandedHeaderHeight: 0)
    #expect(music.expandedHeight == 186)
}
