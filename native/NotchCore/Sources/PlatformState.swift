import Foundation
import NotchProtocol

public struct SurfaceKey: Hashable, Sendable, Identifiable {
    public let extensionID: String
    public let surfaceID: String
    public var id: String { "\(extensionID)/\(surfaceID)" }
    public init(extensionID: String, surfaceID: String) { self.extensionID = extensionID; self.surfaceID = surfaceID }
}

public struct HostedSurface: Identifiable, Sendable {
    public let key: SurfaceKey
    public var surface: Surface
    public var id: SurfaceKey { key }
}

public enum NotchPresentation: Sendable { case idle, compact, hovered, peek, expanded }

public struct ActivePeek: Equatable, Sendable {
    public let key: SurfaceKey
    public let eventID: String
    public let expiresAt: Date
}

/// Presentation is host-owned. Closing a panel never resolves an extension's prompt.
public struct PlatformState: Sendable {
    public private(set) var surfaces: [HostedSurface] = []
    public private(set) var selection: SurfaceKey?
    public private(set) var isExpanded = false
    public private(set) var activePeek: ActivePeek?
    private var compactSelection: SurfaceKey?
    private var revisions: [String: Int] = [:]
    private var consumedPeeks: [SurfaceKey: String] = [:]
    private var recentActivities: [SurfaceKey] = []

    public init() {}
    public var presentation: NotchPresentation {
        if isExpanded { return .expanded }
        if activePeek != nil { return .peek }
        return compact != nil || pendingCount > 0 ? .compact : .idle
    }
    public var selected: HostedSurface? { surfaces.first { $0.key == selection } }
    public var peeking: HostedSurface? { surfaces.first { $0.key == activePeek?.key } }
    public var compact: HostedSurface? {
        // Installed/paused activities remain in the switcher without claiming the notch.
        let visible = surfaces.filter { $0.surface.compact != nil && $0.surface.phase != .paused }
        return peeking
            ?? visible.first { $0.key == compactSelection }
            ?? visible.first { $0.surface.kind == .activity }
            ?? visible.first
    }
    public var pendingCount: Int { surfaces.filter { $0.surface.kind == .prompt }.count }

    /// Hover is a deliberate request for context, so it can reveal a paused
    /// activity without letting that activity claim the resting notch.
    public var hoverSurface: HostedSurface? {
        if let compact { return compact }
        if let pending = surfaces.first(where: { $0.surface.kind == .prompt && $0.surface.phase == .pending }) {
            return pending
        }
        for key in recentActivities {
            if let recent = surfaces.first(where: { $0.key == key && $0.surface.compact != nil }) { return recent }
        }
        return surfaces.first { $0.surface.kind == .activity && $0.surface.idlePreview == true && $0.surface.compact != nil }
    }

    public mutating func apply(_ snapshot: Snapshot, expectedExtensionID: String,
                               now: Date = .now, allowPeek: Bool = true) throws {
        try snapshot.validate(expectedExtensionID: expectedExtensionID)
        guard snapshot.revision > revisions[snapshot.extensionID, default: 0] else { return }
        revisions[snapshot.extensionID] = snapshot.revision
        let oldIDs = Set(surfaces.filter { $0.key.extensionID == snapshot.extensionID }.map(\.key.surfaceID))
        let previousPhases = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.key, $0.surface.phase) })
        let replacements = snapshot.surfaces.map {
            HostedSurface(key: .init(extensionID: snapshot.extensionID, surfaceID: $0.id), surface: $0)
        }
        // Preserve insertion order so ticking snapshots never shuffle the activity switcher.
        var incoming = replacements
        surfaces = surfaces.compactMap { item in
            guard item.key.extensionID == snapshot.extensionID else { return item }
            guard let index = incoming.firstIndex(where: { $0.key == item.key }) else { return nil }
            return incoming.remove(at: index)
        } + incoming
        recentActivities.removeAll { key in !surfaces.contains { $0.key == key } }
        for item in replacements where item.surface.kind == .activity && item.surface.compact != nil &&
            item.surface.phase != .paused && previousPhases[item.key] != item.surface.phase {
            remember(item.key)
        }
        consumedPeeks = consumedPeeks.filter { entry in surfaces.contains { $0.key == entry.key } }
        let announcements = replacements.filter {
            guard $0.surface.phase != .paused, let peek = $0.surface.peek else { return false }
            return consumedPeeks[$0.key] != peek.id
        }
        // A preloaded, paused track has not started its event yet. Active events
        // are consumed even when a panel is open, so closing never replays them.
        for item in replacements where item.surface.phase != .paused {
            if let peek = item.surface.peek { consumedPeeks[item.key] = peek.id }
        }
        if let activePeek, !surfaces.contains(where: {
            $0.key == activePeek.key && $0.surface.peek != nil &&
                ($0.surface.phase != .paused || previousPhases[$0.key] == .paused)
        }) {
            self.activePeek = nil
        }
        if selected == nil { selection = compact?.key; isExpanded = false }
        if !isExpanded, let newcomer = replacements.first(where: {
            !oldIDs.contains($0.surface.id) && $0.surface.initialView == .expanded
        }) {
            selection = newcomer.key
            isExpanded = true
            activePeek = nil
        }
        if selection == nil { selection = compact?.key }
        // Consume events while a user is working in a panel; never replay them on close.
        if !isExpanded, allowPeek, let announcement = announcements.last {
            showPeek(for: announcement.key, now: now)
        }
    }

    public mutating func showPeek(for key: SurfaceKey, now: Date = .now) {
        guard let item = surfaces.first(where: { $0.key == key }), let peek = item.surface.peek else { return }
        isExpanded = false
        compactSelection = key
        selection = key
        consumedPeeks[key] = peek.id
        remember(key)
        activePeek = .init(key: key, eventID: peek.id, expiresAt: now.addingTimeInterval(peek.duration))
    }

    /// The host schedules this deadline; revisions and progress updates never extend it.
    public mutating func expirePeek(now: Date = .now) {
        guard let activePeek, now >= activePeek.expiresAt else { return }
        self.activePeek = nil
    }

    public mutating func open(_ key: SurfaceKey) {
        guard let item = surfaces.first(where: { $0.key == key }) else { return }
        selection = key
        isExpanded = true
        activePeek = nil
        if item.surface.compact != nil { compactSelection = key }
        if item.surface.kind == .activity, item.surface.compact != nil { remember(key) }
    }

    public mutating func toggle() {
        if isExpanded { close() }
        else if let key = hoverSurface?.key { open(key) }
    }

    public mutating func close() {
        isExpanded = false
        activePeek = nil
        selection = compact?.key
    }

    public mutating func removeExtension(_ id: String) {
        surfaces.removeAll { $0.key.extensionID == id }
        revisions.removeValue(forKey: id)
        consumedPeeks = consumedPeeks.filter { $0.key.extensionID != id }
        recentActivities.removeAll { $0.extensionID == id }
        if activePeek?.key.extensionID == id { activePeek = nil }
        if selected == nil { selection = compact?.key; isExpanded = false }
    }

    private mutating func remember(_ key: SurfaceKey) {
        recentActivities.removeAll { $0 == key }
        recentActivities.insert(key, at: 0)
    }
}
