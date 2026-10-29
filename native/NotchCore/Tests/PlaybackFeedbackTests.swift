import Foundation
import Testing
import NotchProtocol
@testable import NotchCore

private let feedbackStart = Date(timeIntervalSince1970: 1_000)
private func playback(id: String = "track", position: Double = 20, playing: Bool = true,
                      at date: Date = feedbackStart) -> NowPlayingState {
    .init(id: id, eventID: id, player: .spotify, title: "Song", artist: "Artist", duration: 200,
          position: position, isPlaying: playing, updatedAt: date.timeIntervalSince1970)
}

@Test func seekingHoldsTheClickedPositionWhileAnOldPlayerSampleArrives() throws {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .seek, value: 0.75), state: old, now: feedbackStart)
    #expect(feedback.displayed(old, now: feedbackStart).position == 150)
    let stale = playback(position: 20.2, at: feedbackStart.addingTimeInterval(0.2))
    let update = feedback.receive(stale, now: feedbackStart.addingTimeInterval(0.2))
    let displayed = try #require(update)
    #expect(abs(displayed.position - 150.2) < 0.001)
    #expect(feedback.hasPending)
}

@Test func confirmedSeekHandsBackToThePlayerWithoutAnotherJump() throws {
    var feedback = PlaybackFeedback()
    feedback.begin(.init(command: .seek, value: 0.75), state: playback(), now: feedbackStart)
    let confirmation = playback(position: 150.3, at: feedbackStart.addingTimeInterval(0.3))
    let update = feedback.receive(confirmation, now: feedbackStart.addingTimeInterval(0.4))
    let displayed = try #require(update)
    #expect(abs(displayed.position - 150.4) < 0.001)
    #expect(!feedback.hasPending)
}

@Test func anOldTimestampCannotAcknowledgeEvenACoincidentallyMatchingPosition() {
    var feedback = PlaybackFeedback()
    feedback.begin(.init(command: .seek, value: 0.5), state: playback(), now: feedbackStart)
    feedback.receive(playback(position: 100, at: feedbackStart.addingTimeInterval(-1)), now: feedbackStart)
    #expect(feedback.hasPending)
}

@Test func rapidSeeksKeepTheLastTargetWhenTheFirstAcknowledgementArrives() throws {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .seek, value: 0.8), state: old, now: feedbackStart)
    feedback.begin(.init(command: .seek, value: 0.2), state: old, now: feedbackStart.addingTimeInterval(0.1))
    let firstAck = playback(position: 160.2, at: feedbackStart.addingTimeInterval(0.2))
    let update = feedback.receive(firstAck, now: feedbackStart.addingTimeInterval(0.2))
    let displayed = try #require(update)
    #expect(abs(displayed.position - 40.1) < 0.001)
    #expect(feedback.hasPending)
}

@Test func pauseChangesTheIconAndFreezesProgressImmediately() throws {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .playPause), state: old, now: feedbackStart)
    let update = feedback.receive(playback(position: 21, at: feedbackStart.addingTimeInterval(1)), now: feedbackStart.addingTimeInterval(1))
    let displayed = try #require(update)
    #expect(!displayed.isPlaying)
    #expect(displayed.position == 20)
    #expect(feedback.hasPending)
    feedback.receive(playback(position: 20, playing: false, at: feedbackStart.addingTimeInterval(1.1)), now: feedbackStart.addingTimeInterval(1.1))
    #expect(!feedback.hasPending)
}

@Test func rapidPauseAndPlayDoNotFlashTheIntermediatePausedState() throws {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .playPause), state: old, now: feedbackStart)
    feedback.begin(.init(command: .playPause), state: old, now: feedbackStart.addingTimeInterval(0.1))
    let intermediate = playback(position: 20, playing: false, at: feedbackStart.addingTimeInterval(0.2))
    let update = feedback.receive(intermediate, now: feedbackStart.addingTimeInterval(0.2))
    let displayed = try #require(update)
    #expect(displayed.isPlaying)
    #expect(abs(displayed.position - 20.1) < 0.001)
    #expect(feedback.hasPending)
}

@Test func aFailedOldCommandCannotRollBackANewerSeek() {
    var feedback = PlaybackFeedback()
    let old = playback()
    let first = feedback.begin(.init(command: .seek, value: 0.8), state: old, now: feedbackStart)
    feedback.begin(.init(command: .seek, value: 0.2), state: old, now: feedbackStart.addingTimeInterval(0.1))
    feedback.reject(first)
    #expect(feedback.displayed(old, now: feedbackStart.addingTimeInterval(0.1)).position == 40)
    #expect(feedback.hasPending)
}

@Test func rejectingACommandRestoresAuthoritativeStateButKeepsOtherPendingFields() {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .shuffle), state: old, now: feedbackStart)
    let seek = feedback.begin(.init(command: .seek, value: 0.8), state: old, now: feedbackStart)
    feedback.reject(seek)
    let displayed = feedback.displayed(old, now: feedbackStart)
    #expect(displayed.position == 20)
    #expect(displayed.shuffle)
}

@Test func missingAcknowledgementExpiresInsteadOfKeepingAnIncorrectStateForever() throws {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .seek, value: 0.8), state: old, now: feedbackStart)
    let deadline = feedbackStart.addingTimeInterval(PlaybackFeedback.acknowledgementTimeout)
    let update = feedback.receive(old, now: deadline)
    let displayed = try #require(update)
    #expect(displayed.position == 20 + PlaybackFeedback.acknowledgementTimeout)
    #expect(!feedback.hasPending)
}

@Test func changingTracksOrRemovingPlaybackDiscardsPendingIntent() throws {
    var feedback = PlaybackFeedback()
    feedback.begin(.init(command: .seek, value: 0.8), state: playback(), now: feedbackStart)
    let next = playback(id: "next", position: 0, playing: false)
    let update = feedback.receive(next, now: feedbackStart)
    let displayed = try #require(update)
    #expect(displayed.position == 0)
    #expect(!feedback.hasPending)
    feedback.begin(.init(command: .playPause), state: next, now: feedbackStart)
    let removed = feedback.receive(nil)
    #expect(removed == nil)
    #expect(!feedback.hasPending)
}

@Test func pendingPlaybackNeverAdvancesPastTheEndOfTheTrack() {
    var feedback = PlaybackFeedback()
    feedback.begin(.init(command: .seek, value: 1), state: playback(), now: feedbackStart)
    #expect(feedback.displayed(playback(), now: feedbackStart.addingTimeInterval(1)).position == 200)
}

@Test func shuffleRepeatAndVolumeWaitForTheirOwnAcknowledgements() throws {
    var feedback = PlaybackFeedback()
    let old = playback()
    feedback.begin(.init(command: .shuffle), state: old, now: feedbackStart)
    feedback.begin(.init(command: .repeatMode), state: old, now: feedbackStart)
    feedback.begin(.init(command: .volume, value: 0.4), state: old, now: feedbackStart)
    var sample = old
    sample.updatedAt += 0.1
    sample.shuffle = true
    let update = feedback.receive(sample, now: feedbackStart.addingTimeInterval(0.1))
    let displayed = try #require(update)
    #expect(displayed.shuffle)
    #expect(displayed.repeating)
    #expect(displayed.volume == 0.4)
    #expect(feedback.hasPending)
    sample.repeating = true
    sample.volume = 0.4
    feedback.receive(sample, now: feedbackStart.addingTimeInterval(0.1))
    #expect(!feedback.hasPending)
}
