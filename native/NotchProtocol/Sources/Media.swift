import Foundation

public enum MediaCommand: String, Codable, Sendable {
    case playPause, previous, next, seek, volume, shuffle, repeatMode = "repeat", openPlayer
}

public struct NowPlayingState: Codable, Equatable, Sendable {
    public var id: String
    public var eventID: String
    public var player: String
    public var playerName: String?
    public var title: String
    public var artist: String
    public var album: String
    public var artwork: String?
    public var duration: Double
    public var position: Double
    public var isPlaying: Bool
    public var volume: Double
    public var shuffle: Bool
    public var repeating: Bool
    public var updatedAt: Double

    public init(id: String, eventID: String, player: String, playerName: String? = nil, title: String, artist: String,
                album: String = "", artwork: String? = nil, duration: Double, position: Double,
                isPlaying: Bool, volume: Double = 1, shuffle: Bool = false, repeating: Bool = false,
                updatedAt: Double = Date.now.timeIntervalSince1970) {
        self.id = id; self.eventID = eventID; self.player = player; self.title = title; self.artist = artist
        self.playerName = playerName; self.album = album; self.artwork = artwork; self.duration = duration; self.position = position
        self.isPlaying = isPlaying; self.volume = volume; self.shuffle = shuffle; self.repeating = repeating
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !id.isEmpty, id.count <= 512, !eventID.isEmpty, eventID.count <= 128,
              !player.isEmpty, player.count <= 128, (playerName?.count ?? 0) <= 128,
              !title.isEmpty, title.count <= 256, artist.count <= 256, album.count <= 256,
              duration.isFinite, (0...604_800).contains(duration),
              position.isFinite, (0...604_800).contains(position),
              volume.isFinite, (0...1).contains(volume), updatedAt.isFinite,
              artwork == nil || Self.isArtworkSource(artwork!) else {
            throw ProtocolError.invalid("Invalid now-playing state")
        }
    }

    public static func isArtworkSource(_ source: String) -> Bool {
        if source.hasPrefix("data:image/jpeg;base64,") || source.hasPrefix("data:image/png;base64,") {
            return source.utf8.count <= 65_536
        }
        guard source.count <= 2048, let url = URL(string: source), url.scheme == "https",
              let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return host == "i.scdn.co" || host == "mosaic.scdn.co" || host.hasSuffix(".mzstatic.com")
    }
}

public struct MediaRequest: Codable, Sendable {
    public var command: MediaCommand
    public var value: Double?
    public init(command: MediaCommand, value: Double? = nil) { self.command = command; self.value = value }
    public func validate() throws {
        if command == .seek || command == .volume {
            guard let value, value.isFinite, (0...1).contains(value) else {
                throw ProtocolError.invalid("Media position and volume must be between zero and one")
            }
        } else if value != nil { throw ProtocolError.invalid("This media command takes no value") }
    }
}
