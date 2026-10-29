import AppKit
import Carbon
import ImageIO
import Observation
import NotchProtocol
import NotchCore

/// All Apple events are serialized off the UI thread. Targets and commands are fixed;
/// extension strings are never interpolated into executable scripts.
private actor MusicAutomation {
    func permission(for player: MediaPlayer, ask: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard),
                                                    AEEventID(typeWildCard), ask) == noErr
    }

    func read(_ player: MediaPlayer) throws -> NowPlayingState? {
        let fields: String
        if player == .spotify {
            fields = "{id of t, name of t, artist of t, album of t, artwork url of t, duration of t, player position, sound volume, shuffling, repeating, player state as string}"
        } else {
            fields = "{persistent ID of t, name of t, artist of t, album of t, art, duration of t, player position, sound volume, shuffle enabled, (song repeat is not off), player state as string}"
        }
        let artwork = player == .music ? "set art to missing value\ntry\nset art to raw data of artwork 1 of t\nend try" : ""
        let result = try execute("""
        with timeout of 2 seconds
          tell application id "\(player.rawValue)"
            if player state is stopped then return {}
            set t to current track
            \(artwork)
            return \(fields)
          end tell
        end timeout
        """)
        guard result.numberOfItems == 11 else { return nil }
        func text(_ index: Int) -> String { String((result.atIndex(index)?.stringValue ?? "").prefix(256)) }
        func number(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }
        var source: String?
        if player == .spotify { source = text(5) }
        else if let data = result.atIndex(5)?.data, let jpg = Self.thumbnail(data) {
            source = "data:image/jpeg;base64," + jpg.base64EncodedString()
        }
        if let value = source, !NowPlayingState.isArtworkSource(value) { source = nil }
        let duration = min(604_800, max(0, number(6) / (player == .spotify ? 1000 : 1)))
        let state = NowPlayingState(id: player.rawValue + ":" + text(1), eventID: "pending", player: player,
            title: text(2), artist: text(3), album: text(4), artwork: source, duration: duration,
            position: min(duration, max(0, number(7))), isPlaying: text(11) == "playing",
            volume: min(1, max(0, number(8) / 100)), shuffle: result.atIndex(9)?.booleanValue ?? false,
            repeating: result.atIndex(10)?.booleanValue ?? false)
        guard !state.title.isEmpty else { return nil }
        try state.validate()
        return state
    }

    func perform(_ request: MediaRequest, state: NowPlayingState) throws {
        try request.validate()
        let command: String
        switch request.command {
        case .playPause: command = state.isPlaying ? "pause" : "play"
        case .next: command = "next track"
        case .previous: command = "previous track"
        case .seek: command = "set player position to \((request.value ?? 0) * state.duration)"
        case .volume: command = "set sound volume to \(Int((request.value ?? 0) * 100))"
        case .shuffle:
            command = state.player == .spotify ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled"
        case .repeatMode:
            command = state.player == .spotify ? "set repeating to not repeating" : "set song repeat to \(state.repeating ? "off" : "all")"
        case .openPlayer: return
        }
        _ = try execute("with timeout of 2 seconds\ntell application id \"\(state.player.rawValue)\"\n\(command)\nend tell\nend timeout")
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw ProtocolError.invalid("Could not connect to the music player") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw ProtocolError.invalid("Allow NotchNotch in System Settings → Privacy & Security → Automation") }
            throw ProtocolError.invalid(error[NSAppleScript.errorMessage] as? String ?? "The music player did not respond")
        }
        return result
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumb, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length < 45_000 else { return nil }
        return output as Data
    }
}

@MainActor @Observable
final class MusicProvider {
    private(set) var state: NowPlayingState?
    private(set) var errors: [MediaPlayer: String] = [:]
    private(set) var lastCommandError: String?
    private(set) var authorized: Set<MediaPlayer> = []
    var onChange: ((NowPlayingState?) -> Void)?
    private let automation = MusicAutomation()
    private let spotifyCommands = SpotifyCommands()
    private var feedback = PlaybackFeedback()
    private var confirmedState: NowPlayingState?
    private var commandRevision = 0
    private var refreshRequested = false
    private struct QueuedCommand {
        let request: MediaRequest
        let state: NowPlayingState
        let token: UUID
    }
    private var commands: [QueuedCommand] = []
    private var commandTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var refreshing = false
    private var eventID = UUID().uuidString
    private var lastSamples: [MediaPlayer: NowPlayingState] = [:]

    func start() {
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(self.state?.isPlaying == true ? 1 : 3)) }
                catch { return }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        confirmationTask?.cancel()
        commandTask?.cancel()
        commands.removeAll()
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers.removeAll()
    }

    func connect(_ player: MediaPlayer) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) != nil else {
            errors[player] = "\(player.name) is not installed"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if await self.automation.permission(for: player, ask: true) {
                self.authorized.insert(player)
                self.errors[player] = nil
                await self.refresh()
            } else { self.errors[player] = "Allow NotchNotch to control \(player.name) in System Settings → Privacy & Security → Automation" }
        }
    }

    func perform(_ request: MediaRequest) {
        guard let state else { return }
        if request.command == .openPlayer {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.player.rawValue) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        guard authorized.contains(state.player), (try? request.validate()) != nil else { return }
        lastCommandError = nil
        commandRevision += 1
        let token = feedback.begin(request, state: state)
        self.state = feedback.displayed(state)
        onChange?(self.state)
        commands.append(.init(request: request, state: state, token: token))
        drainCommands()
    }

    private func drainCommands() {
        guard commandTask == nil else { return }
        commandTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.commandTask = nil }
            while !Task.isCancelled, !self.commands.isEmpty {
                let command = self.commands.removeFirst()
                do {
                    if command.state.player == .spotify {
                        try await self.spotifyCommands.perform(command.request, state: command.state)
                    } else {
                        try await self.automation.perform(command.request, state: command.state)
                    }
                    guard !Task.isCancelled else { return }
                    self.errors[command.state.player] = nil
                    self.confirmPendingCommands()
                } catch {
                    self.lastCommandError = error.localizedDescription
                    self.feedback.reject(command.token)
                    self.errors[command.state.player] = error.localizedDescription
                    self.state = self.confirmedState.map { self.feedback.displayed($0) }
                    self.onChange?(self.state)
                }
                // Reads run independently: a second click never waits for the
                // previous command's metadata confirmation before it is sent.
                Task { [weak self] in await self?.refresh() }
            }
        }
    }

    private func confirmPendingCommands() {
        confirmationTask?.cancel()
        guard feedback.hasPending else { return }
        confirmationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.feedback.hasPending else { return }
                do { try await Task.sleep(for: .milliseconds(120)) }
                catch { return }
                await self.refresh()
            }
        }
    }

    private func refresh() async {
        guard !refreshing else { refreshRequested = true; return }
        refreshing = true
        let revision = commandRevision
        defer {
            refreshing = false
            if refreshRequested {
                refreshRequested = false
                Task { [weak self] in await self?.refresh() }
            }
        }
        var candidates: [NowPlayingState] = []
        for player in MediaPlayer.allCases {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).contains(where: { !$0.isTerminated }) else { continue }
            if !authorized.contains(player), await automation.permission(for: player, ask: false) { authorized.insert(player) }
            guard authorized.contains(player) else { continue }
            do {
                if let sample = try await automation.read(player) {
                    lastSamples[player] = sample
                    candidates.append(sample)
                } else { lastSamples[player] = nil }
                errors[player] = nil
            } catch {
                errors[player] = error.localizedDescription
                if let previous = lastSamples[player], Date.now.timeIntervalSince1970 - previous.updatedAt < 5 {
                    candidates.append(previous)
                }
            }
        }
        // A sample whose read began before a command must never overwrite its intent,
        // even if a later confirmation has already cleared the optimistic overlay.
        guard revision == commandRevision else { refreshRequested = true; return }
        // Keep the current playing source stable when more than one player is open.
        var next = candidates.first { $0.player == state?.player && $0.isPlaying }
            ?? candidates.first { $0.isPlaying }
            ?? candidates.first { $0.player == state?.player }
            ?? candidates.first
        let looped = next?.id == state?.id && next?.isPlaying == true && state?.isPlaying == true &&
            (state?.duration ?? 0) > 5 && (state?.position ?? 0) > (state?.duration ?? 0) - 3 && (next?.position ?? 4) < 3
        if next?.id != state?.id || looped { eventID = UUID().uuidString }
        next?.eventID = eventID
        confirmedState = next
        state = feedback.receive(next)
        onChange?(state)
    }
}
