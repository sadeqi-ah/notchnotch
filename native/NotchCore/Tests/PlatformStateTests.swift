import Foundation
import Testing
import NotchProtocol
@testable import NotchCore

private func activity(id: String = "timer") -> Surface {
    .init(id: id, kind: .activity, title: "Timer", compact: .init(leading: [], trailing: []),
          expanded: .init(id: "\(id)-body", type: .column))
}
private func prompt() -> Surface {
    .init(id: "question", kind: .prompt, title: "Question", initialView: .expanded, phase: .pending,
          expanded: .init(id: "question-body", type: .column))
}

@Test func promptDoesNotReplaceAnOpenActivity() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    state.toggle()
    let selection = state.selection
    try state.apply(.init(extensionID: "questions", revision: 1, surfaces: [prompt()]), expectedExtensionID: "questions")
    #expect(state.selection == selection)
    #expect(state.isExpanded)
    #expect(state.pendingCount == 1)
}

@Test func expandedOnlyPromptOpensButClosingItPreservesTheRequest() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    try state.apply(.init(extensionID: "questions", revision: 1, surfaces: [prompt()]), expectedExtensionID: "questions")
    #expect(state.isExpanded)
    #expect(state.selected?.surface.kind == .prompt)
    state.close()
    #expect(!state.isExpanded)
    #expect(state.pendingCount == 1)
    #expect(state.compact?.surface.kind == .activity)
    // A routine render is not a new request and must not reopen the panel.
    try state.apply(.init(extensionID: "questions", revision: 2, surfaces: [prompt()]), expectedExtensionID: "questions")
    #expect(!state.isExpanded)
}

@Test func staleSnapshotsAndCrashesCannotResurrectOldState() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 2, surfaces: [activity()]), expectedExtensionID: "timer")
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: []), expectedExtensionID: "timer")
    #expect(state.surfaces.count == 1)
    state.removeExtension("timer")
    #expect(state.surfaces.isEmpty)
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    #expect(state.surfaces.count == 1)
}

@Test func surfaceIdentityIsNamespacedByExtension() throws {
    var state = PlatformState()
    for id in ["first", "second"] {
        try state.apply(.init(extensionID: id, revision: 1, surfaces: [activity()]), expectedExtensionID: id)
    }
    #expect(Set(state.surfaces.map(\.key)).count == 2)
}

@Test func resolvingSelectedPromptReturnsToCompactActivity() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    try state.apply(.init(extensionID: "questions", revision: 1, surfaces: [prompt()]), expectedExtensionID: "questions")
    try state.apply(.init(extensionID: "questions", revision: 2, surfaces: []), expectedExtensionID: "questions")
    #expect(!state.isExpanded)
    #expect(state.selected?.surface.kind == .activity)
    #expect(state.pendingCount == 0)
}

@Test func malformedSnapshotIsRejectedBeforeStateChanges() throws {
    var state = PlatformState()
    var invalid = prompt()
    invalid.initialView = .compact
    #expect(throws: ProtocolError.self) {
        try state.apply(.init(extensionID: "questions", revision: 1, surfaces: [invalid]), expectedExtensionID: "questions")
    }
    #expect(state.surfaces.isEmpty)
    #expect(throws: ProtocolError.self) {
        try Snapshot(extensionID: "spoofed", revision: 1, surfaces: []).validate(expectedExtensionID: "questions")
    }
    var duplicate = activity()
    duplicate.expanded.children = [duplicate.expanded]
    #expect(throws: ProtocolError.self) {
        try Snapshot(extensionID: "timer", revision: 1, surfaces: [duplicate]).validate(expectedExtensionID: "timer")
    }
}

@Test func compactRemainsOneClickTarget() throws {
    var surface = activity()
    surface.compact = .init(leading: [.init(id: "nested-button", type: .button)], trailing: [])
    #expect(throws: ProtocolError.self) {
        try Snapshot(extensionID: "timer", revision: 1, surfaces: [surface]).validate(expectedExtensionID: "timer")
    }
}

private let peekStart = Date(timeIntervalSince1970: 1_000)
private func announcement(id: String = "track-1", duration: Double = 4) -> Surface {
    var surface = activity(id: "music")
    surface.peek = .init(id: id, text: "Katerina • Thisavros Mou", duration: duration)
    return surface
}

@Test func announcementReturnsToTheSameCompactActivityAtItsDeadline() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music", now: peekStart)
    #expect(state.presentation == .peek)
    #expect(state.peeking?.key == state.compact?.key)
    #expect(state.compact?.key.extensionID == "music")
    state.expirePeek(now: peekStart.addingTimeInterval(3.99))
    #expect(state.presentation == .peek)
    state.expirePeek(now: peekStart.addingTimeInterval(4))
    #expect(state.presentation == .compact)
    #expect(state.compact?.key.extensionID == "music")
    #expect(state.surfaces.count == 2)
}

@Test func routineRendersNeverRestartOrReplayAnAnnouncement() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music", now: peekStart)
    let deadline = state.activePeek?.expiresAt
    var updated = announcement(duration: 10)
    updated.peek?.text = "Metadata corrected"
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [updated]), expectedExtensionID: "music", now: peekStart.addingTimeInterval(3))
    #expect(state.activePeek?.expiresAt == deadline)
    #expect(state.peeking?.surface.peek?.text == "Metadata corrected")
    state.expirePeek(now: peekStart.addingTimeInterval(4))
    try state.apply(.init(extensionID: "music", revision: 3, surfaces: [updated]), expectedExtensionID: "music", now: peekStart.addingTimeInterval(5))
    #expect(state.presentation == .compact)
}

@Test func aNewEventReplacesThePreviousAnnouncementAndGetsItsOwnDeadline() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music", now: peekStart)
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [announcement(id: "track-2")]), expectedExtensionID: "music", now: peekStart.addingTimeInterval(3))
    state.expirePeek(now: peekStart.addingTimeInterval(4))
    #expect(state.activePeek?.eventID == "track-2")
    #expect(state.activePeek?.expiresAt == peekStart.addingTimeInterval(7))
    state.expirePeek(now: peekStart.addingTimeInterval(7))
    #expect(state.presentation == .compact)
}

@Test func announcementsNeverInterruptAnOpenPanelOrReplayAfterClosing() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    state.toggle()
    let selection = state.selection
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music", now: peekStart)
    #expect(state.presentation == .expanded)
    #expect(state.selection == selection)
    #expect(state.activePeek == nil)
    state.close()
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.presentation == .compact)
}

@Test func hoverPreviewCanDeferAnAnnouncementWithoutReplayingIt() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music", allowPeek: false)
    #expect(state.activePeek == nil)
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.activePeek == nil)
}

@Test func clickingAnAnnouncementPinsThePanelAndCancelsItsExpiry() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music", now: peekStart)
    state.toggle()
    #expect(state.presentation == .expanded)
    #expect(state.selected?.key.extensionID == "music")
    #expect(state.activePeek == nil)
    state.expirePeek(now: peekStart.addingTimeInterval(30))
    #expect(state.isExpanded)
}

@Test func dismissingAnAnnouncementDoesNotRemoveTheActivityOrReplayTheEvent() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music")
    state.close()
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.presentation == .compact)
    #expect(state.surfaces.count == 1)
}

@Test func pendingPromptTakesPrecedenceOverAnAutomaticAnnouncement() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement(), prompt()]), expectedExtensionID: "music")
    #expect(state.presentation == .expanded)
    #expect(state.selected?.surface.kind == .prompt)
    #expect(state.activePeek == nil)
}

@Test func removingAnAnnouncementOrItsExtensionCancelsThePeek() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music")
    var noPeek = announcement()
    noPeek.peek = nil
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [noPeek]), expectedExtensionID: "music")
    #expect(state.presentation == .compact)
    try state.apply(.init(extensionID: "music", revision: 3, surfaces: [announcement(id: "next")]), expectedExtensionID: "music")
    state.removeExtension("unrelated")
    #expect(state.presentation == .peek)
    state.removeExtension("music")
    #expect(state.presentation == .idle)
    #expect(state.surfaces.isEmpty)
}

@Test func staleSnapshotsCannotReplaceAnAnnouncement() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [announcement()]), expectedExtensionID: "music", now: peekStart)
    let peek = state.activePeek
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement(id: "stale")]), expectedExtensionID: "music")
    #expect(state.activePeek == peek)
}

@Test func malformedAnnouncementsAreRejectedBeforeChangingPresentation() throws {
    var state = PlatformState()
    for duration in [0.0, 0.5, 11, .infinity, .nan] {
        #expect(throws: ProtocolError.self) {
            try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement(duration: duration)]), expectedExtensionID: "music")
        }
    }
    var missingCompact = announcement()
    missingCompact.compact = nil
    missingCompact.initialView = .expanded
    var emptyText = announcement()
    emptyText.peek?.text = ""
    var oversizedID = announcement()
    oversizedID.peek?.id = String(repeating: "a", count: 129)
    var promptWithPeek = prompt()
    promptWithPeek.peek = announcement().peek
    for invalid in [missingCompact, emptyText, oversizedID, promptWithPeek] {
        #expect(throws: ProtocolError.self) {
            try state.apply(.init(extensionID: "music", revision: 1, surfaces: [invalid]), expectedExtensionID: "music")
        }
    }
    #expect(state.surfaces.isEmpty)
    #expect(state.activePeek == nil)
}

@Test func pausedExtensionsDoNotClaimTheIdleNotch() throws {
    var state = PlatformState()
    #expect(state.presentation == .idle)
    var paused = announcement()
    paused.phase = .paused
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [paused]), expectedExtensionID: "music")
    #expect(state.presentation == .idle)
    #expect(state.compact == nil)
    #expect(state.surfaces.count == 1)
    state.open(state.surfaces[0].key)
    #expect(state.presentation == .expanded)
    state.close()
    #expect(state.presentation == .idle)
}

@Test func playbackActivatesTheNotchAndPausingHidesItAgain() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.presentation == .peek)
    var paused = announcement()
    paused.phase = .paused
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [paused]), expectedExtensionID: "music")
    #expect(state.activePeek == nil)
    #expect(state.presentation == .idle)
    try state.apply(.init(extensionID: "music", revision: 3, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.presentation == .compact)
}

@Test func pendingPromptCanClaimTheNotchEvenWithoutCompactContent() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "questions", revision: 1, surfaces: [prompt()]), expectedExtensionID: "questions")
    state.close()
    #expect(state.presentation == .compact)
    #expect(state.pendingCount == 1)
}

@Test func aPreloadedPausedTrackAnnouncesWhenItFirstStartsButResumingDoesNotReplayIt() throws {
    var state = PlatformState()
    var paused = announcement()
    paused.phase = .paused
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [paused]), expectedExtensionID: "music")
    #expect(state.presentation == .idle)
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.presentation == .peek)
    state.close()
    try state.apply(.init(extensionID: "music", revision: 3, surfaces: [paused]), expectedExtensionID: "music")
    try state.apply(.init(extensionID: "music", revision: 4, surfaces: [announcement()]), expectedExtensionID: "music")
    #expect(state.presentation == .compact)
}

private func idleActivity(id: String = "music", eligible: Bool = false) -> Surface {
    var surface = activity(id: id)
    surface.phase = .paused
    surface.idlePreview = eligible
    return surface
}

@Test func unusedPausedExtensionsDoNotBecomeIdleHoverContent() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "demos", revision: 1,
                          surfaces: [idleActivity(id: "timer"), idleActivity(id: "questions")]), expectedExtensionID: "demos")
    #expect(state.presentation == .idle)
    #expect(state.hoverSurface == nil)
}

@Test func resumableContentCanAppearOnHoverWithoutClaimingTheIdleNotch() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [idleActivity(eligible: true)]), expectedExtensionID: "music")
    #expect(state.presentation == .idle)
    #expect(state.compact == nil)
    #expect(state.hoverSurface?.key.extensionID == "music")
    state.toggle()
    #expect(state.selected?.key.extensionID == "music")
    #expect(state.presentation == .expanded)
    state.close()
    #expect(state.presentation == .idle)
    #expect(state.hoverSurface?.key.extensionID == "music")
}

@Test func theLastActivityUsedByTheUserWinsOverAnIdleFallback() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [idleActivity(eligible: true)]), expectedExtensionID: "music")
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [idleActivity(id: "timer")]), expectedExtensionID: "timer")
    state.open(.init(extensionID: "timer", surfaceID: "timer"))
    state.close()
    #expect(state.hoverSurface?.key.extensionID == "timer")
    // Routine metadata refreshes do not make a different idle extension more recent.
    try state.apply(.init(extensionID: "music", revision: 2, surfaces: [idleActivity(eligible: true)]), expectedExtensionID: "music")
    #expect(state.hoverSurface?.key.extensionID == "timer")
}

@Test func activeWorkWinsOverARecentPausedActivity() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [idleActivity(id: "timer")]), expectedExtensionID: "timer")
    state.open(.init(extensionID: "timer", surfaceID: "timer"))
    state.close()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [activity(id: "music")]), expectedExtensionID: "music")
    #expect(state.hoverSurface?.key == state.compact?.key)
    #expect(state.hoverSurface?.key.extensionID == "music")
}

@Test func aPendingQuestionWinsOverResumableOrRecentIdleActivities() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [idleActivity(eligible: true)]), expectedExtensionID: "music")
    try state.apply(.init(extensionID: "questions", revision: 1, surfaces: [prompt()]), expectedExtensionID: "questions")
    state.close()
    #expect(state.hoverSurface?.surface.kind == .prompt)
    state.toggle()
    #expect(state.selected?.surface.kind == .prompt)
}

@Test func previouslyActiveWorkCanBeResumedFromHoverWithoutAnExtensionOptIn() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [activity()]), expectedExtensionID: "timer")
    try state.apply(.init(extensionID: "timer", revision: 2, surfaces: [idleActivity(id: "timer")]), expectedExtensionID: "timer")
    #expect(state.presentation == .idle)
    #expect(state.hoverSurface?.key.extensionID == "timer")
    state.removeExtension("timer")
    #expect(state.hoverSurface == nil)
}

@Test func removingARecentActivityFallsBackToResumableContent() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "music", revision: 1, surfaces: [idleActivity(eligible: true)]), expectedExtensionID: "music")
    try state.apply(.init(extensionID: "timer", revision: 1, surfaces: [idleActivity(id: "timer")]), expectedExtensionID: "timer")
    state.open(.init(extensionID: "timer", surfaceID: "timer"))
    state.close()
    state.removeExtension("timer")
    #expect(state.hoverSurface?.key.extensionID == "music")
}

@Test func idlePreviewRequiresCompactActivityContent() throws {
    var invalid = prompt()
    invalid.idlePreview = true
    #expect(throws: ProtocolError.self) {
        try Snapshot(extensionID: "questions", revision: 1, surfaces: [invalid]).validate(expectedExtensionID: "questions")
    }
    var expandedOnly = activity()
    expandedOnly.compact = nil
    expandedOnly.initialView = .expanded
    expandedOnly.idlePreview = true
    #expect(throws: ProtocolError.self) {
        try Snapshot(extensionID: "timer", revision: 1, surfaces: [expandedOnly]).validate(expectedExtensionID: "timer")
    }
}
