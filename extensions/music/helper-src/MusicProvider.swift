import AppKit
import Carbon
import ImageIO
import NotchProtocol
import NotchCore

enum MediaPlayer: String, Codable, Sendable, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"
    var name: String { self == .spotify ? "Spotify" : "Apple Music" }
}

/// Permission dialogs have their own actor so a slow metadata read cannot queue
/// an explicit Connect request behind the player.
private actor MusicPermissions {
    func permission(for player: MediaPlayer, ask: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard),
                                                    AEEventID(typeWildCard), ask) == noErr
    }
}

/// Read public Apple-event properties directly. NSAppleScript's internal event
/// loop can stall in a headless helper even inside an AppleScript timeout block.
private actor MusicAutomation {
    func read(_ player: MediaPlayer) throws -> NowPlayingState? {
        let events = PlayerEvents(player: player, deadline: .now.addingTimeInterval(2))
        let playback = try events.get("pPlS").enumCodeValue
        if playback == PlayerEvents.code("kPSS") { return nil }
        let track = try events.get("pTrk")
        func text(_ code: String) throws -> String { String(try events.get(code, of: track).stringValue?.prefix(256) ?? "") }
        let id = try text(player == .spotify ? "ID  " : "pPIS")
        let title = try text("pnam")
        guard !title.isEmpty else { return nil }
        let artist = try text("pArt")
        let album = try text("pAlb")
        let duration = min(604_800, max(0, try events.get("pDur", of: track).doubleValue / (player == .spotify ? 1000 : 1)))
        let position = min(duration, max(0, try events.get("pPos").doubleValue))
        let sampledAt = Date.now.timeIntervalSince1970
        let volume = min(1, max(0, try events.get("pVol").doubleValue / 100))
        let shuffle = try events.get(player == .spotify ? "pShu" : "pShE").booleanValue
        let repeatValue = try events.get(player == .spotify ? "pRep" : "pRpt")
        let repeating = player == .spotify ? repeatValue.booleanValue : repeatValue.enumCodeValue != PlayerEvents.code("kRpO")
        var source: String?
        if player == .spotify { source = try? text("aUrl") }
        else if let artwork = try? PlayerEvents.element("cArt", index: 1, of: track),
                let data = try? events.get("pRaw", of: artwork).data,
                let jpg = Self.thumbnail(data) {
            source = "data:image/jpeg;base64," + jpg.base64EncodedString()
        }
        if let value = source, !NowPlayingState.isArtworkSource(value) { source = nil }
        let state = NowPlayingState(id: player.rawValue + ":" + id, eventID: "pending", player: player.rawValue, playerName: player.name,
            title: title, artist: artist, album: album, artwork: source, duration: duration,
            position: position, isPlaying: playback == PlayerEvents.code("kPSP"), volume: volume,
            shuffle: shuffle, repeating: repeating, updatedAt: sampledAt)
        try state.validate()
        return state
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
        guard CGImageDestinationFinalize(destination), output.length < 36_000 else { return nil }
        return output as Data
    }
}

@MainActor
final class MusicProvider {
    private(set) var state: NowPlayingState?
    private(set) var errors: [MediaPlayer: String] = [:]
    private(set) var lastCommandError: String?
    private(set) var authorized: Set<MediaPlayer> = []
    var onChange: ((NowPlayingState?) -> Void)?
    private let automation = MusicAutomation()
    private let permissions = MusicPermissions()
    private let playerCommands = PlayerCommands()
    private var feedback = PlaybackFeedback()
    private var confirmedState: NowPlayingState?
    private var commandRevision = 0
    private var refreshRequested = false
    private struct QueuedCommand {
        let request: MediaRequest
        let state: NowPlayingState
        let player: MediaPlayer
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

    func connect(_ player: MediaPlayer) async {
        defer { onChange?(state) }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) != nil else {
            errors[player] = "\(player.name) is not installed"
            return
        }
        if await permissions.permission(for: player, ask: true) {
            authorized.insert(player)
            errors[player] = nil
            await refresh()
        } else {
            errors[player] = "Allow the music helper to control \(player.name) in System Settings → Privacy & Security → Automation"
        }
    }

    func perform(_ request: MediaRequest) {
        guard let state, let player = MediaPlayer(rawValue: state.player) else { return }
        if request.command == .openPlayer {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.player) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        guard authorized.contains(player), (try? request.validate()) != nil else { return }
        lastCommandError = nil
        commandRevision += 1
        let token = feedback.begin(request, state: state)
        self.state = feedback.displayed(state)
        onChange?(self.state)
        commands.append(.init(request: request, state: state, player: player, token: token))
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
                    try await self.playerCommands.perform(command.request, state: command.state)
                    guard !Task.isCancelled else { return }
                    self.errors[command.player] = nil
                    self.confirmPendingCommands()
                } catch {
                    self.lastCommandError = error.localizedDescription
                    self.feedback.reject(command.token)
                    self.errors[command.player] = error.localizedDescription
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
            if !authorized.contains(player), await permissions.permission(for: player, ask: false) { authorized.insert(player) }
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
