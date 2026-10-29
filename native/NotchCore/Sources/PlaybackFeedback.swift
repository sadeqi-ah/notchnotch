import Foundation
import NotchProtocol

/// Holds the latest user intent until a fresh player sample acknowledges it.
/// Both the native control and host broker use this to bridge their async hops.
public struct PlaybackFeedback: Sendable {
    public static let acknowledgementTimeout: TimeInterval = 3
    private struct Pending<Value: Sendable>: Sendable {
        let token: UUID
        let value: Value
        let issuedAt: Date
        var expiresAt: Date { issuedAt.addingTimeInterval(acknowledgementTimeout) }
    }
    private struct Clock: Sendable {
        let position: Double
        let playing: Bool
        func position(at date: Date, since issuedAt: Date) -> Double {
            position + (playing ? max(0, date.timeIntervalSince(issuedAt)) : 0)
        }
    }
    private var trackID: String?
    private var position: Pending<Clock>?
    private var playing: Pending<Bool>?
    private var shuffle: Pending<Bool>?
    private var repeating: Pending<Bool>?
    private var volume: Pending<Double>?

    public init() {}
    public var nextExpiry: Date? {
        [position?.expiresAt, playing?.expiresAt, shuffle?.expiresAt, repeating?.expiresAt, volume?.expiresAt]
            .compactMap { $0 }.min()
    }
    public var hasPending: Bool { nextExpiry != nil }

    @discardableResult public mutating func begin(_ request: MediaRequest, state: NowPlayingState,
                                                  now: Date = .now) -> UUID {
        if trackID != state.id { self = .init(); trackID = state.id }
        let current = displayed(state, now: now)
        let token = UUID()
        switch request.command {
        case .seek:
            position = .init(token: token, value: .init(position: min(1, max(0, request.value ?? 0)) * state.duration,
                                                       playing: current.isPlaying), issuedAt: now)
        case .playPause:
            playing = .init(token: token, value: !current.isPlaying, issuedAt: now)
            position = .init(token: token, value: .init(position: current.position, playing: !current.isPlaying), issuedAt: now)
        case .shuffle: shuffle = .init(token: token, value: !current.shuffle, issuedAt: now)
        case .repeatMode: repeating = .init(token: token, value: !current.repeating, issuedAt: now)
        case .volume: volume = .init(token: token, value: min(1, max(0, request.value ?? 0)), issuedAt: now)
        case .previous, .next, .openPlayer: break
        }
        return token
    }

    /// A late confirmation of an older click cannot undo a newer click.
    public mutating func reject(_ token: UUID) {
        if position?.token == token { position = nil }
        if playing?.token == token { playing = nil }
        if shuffle?.token == token { shuffle = nil }
        if repeating?.token == token { repeating = nil }
        if volume?.token == token { volume = nil }
    }

    public mutating func expire(now: Date = .now) {
        if let position, now >= position.expiresAt { self.position = nil }
        if let playing, now >= playing.expiresAt { self.playing = nil }
        if let shuffle, now >= shuffle.expiresAt { self.shuffle = nil }
        if let repeating, now >= repeating.expiresAt { self.repeating = nil }
        if let volume, now >= volume.expiresAt { self.volume = nil }
    }

    @discardableResult public mutating func receive(_ sample: NowPlayingState?, now: Date = .now) -> NowPlayingState? {
        guard let sample else { self = .init(); return nil }
        guard sample.id == trackID else { self = .init(); trackID = sample.id; return sample }
        expire(now: now)
        let sampledAt = Date(timeIntervalSince1970: sample.updatedAt)
        if let playing, sampledAt >= playing.issuedAt, sample.isPlaying == playing.value { self.playing = nil }
        if let position, sampledAt >= position.issuedAt, sample.isPlaying == position.value.playing,
           abs(sample.position - min(sample.duration, position.value.position(at: sampledAt, since: position.issuedAt))) <= 1 {
            self.position = nil
        }
        if let shuffle, sampledAt >= shuffle.issuedAt, sample.shuffle == shuffle.value { self.shuffle = nil }
        if let repeating, sampledAt >= repeating.issuedAt, sample.repeating == repeating.value { self.repeating = nil }
        if let volume, sampledAt >= volume.issuedAt, abs(sample.volume - volume.value) < 0.015 { self.volume = nil }
        return displayed(sample, now: now)
    }

    public func displayed(_ sample: NowPlayingState, now: Date = .now) -> NowPlayingState {
        var result = sample
        result.position = min(sample.duration, sample.position + (sample.isPlaying ? max(0, now.timeIntervalSince1970 - sample.updatedAt) : 0))
        result.updatedAt = now.timeIntervalSince1970
        guard trackID == sample.id else { return result }
        if let position, now < position.expiresAt {
            result.position = min(sample.duration, position.value.position(at: now, since: position.issuedAt))
        }
        if let playing, now < playing.expiresAt { result.isPlaying = playing.value }
        if let shuffle, now < shuffle.expiresAt { result.shuffle = shuffle.value }
        if let repeating, now < repeating.expiresAt { result.repeating = repeating.value }
        if let volume, now < volume.expiresAt { result.volume = volume.value }
        return result
    }
}
