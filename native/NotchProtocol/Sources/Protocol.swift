import Foundation

public let protocolVersion = 1
public let maximumMessageBytes = 262_144

public enum SurfaceKind: String, Codable, Sendable { case activity, prompt }
public enum Presentation: String, Codable, Sendable { case compact, expanded }
public enum SurfacePhase: String, Codable, Sendable { case active, paused, completed, pending }
public enum NodeKind: String, Codable, Sendable { case column, row, text, symbol, progress, button, textField, artwork, waveform, player }
public enum Tone: String, Codable, Sendable { case primary, secondary, accent, success, warning }
public enum TextSize: String, Codable, Sendable { case caption, body, title, timer }

public struct NodeProps: Codable, Equatable, Sendable {
    public var text: String?
    public var name: String?
    public var tone: Tone?
    public var size: TextSize?
    public var value: Double?
    public var action: String?
    public var placeholder: String?
    public var source: String?
    public var media: NowPlayingState?
    public var disabled: Bool?

    public init(text: String? = nil, name: String? = nil, tone: Tone? = nil, size: TextSize? = nil,
                value: Double? = nil, action: String? = nil, placeholder: String? = nil, disabled: Bool? = nil,
                source: String? = nil, media: NowPlayingState? = nil) {
        self.text = text; self.name = name; self.tone = tone; self.size = size
        self.value = value; self.action = action; self.placeholder = placeholder; self.disabled = disabled
        self.source = source; self.media = media
    }
}

public struct UINode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: NodeKind
    public var props: NodeProps
    public var children: [UINode]
    public init(id: String, type: NodeKind, props: NodeProps = .init(), children: [UINode] = []) {
        self.id = id; self.type = type; self.props = props; self.children = children
    }
}

public struct CompactContent: Codable, Equatable, Sendable {
    public var leading: [UINode]
    public var trailing: [UINode]
    public init(leading: [UINode], trailing: [UINode]) { self.leading = leading; self.trailing = trailing }
}

/// A new id announces a new event. Ordinary snapshots keep the same id.
public struct PeekContent: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var duration: Double
    public init(id: String, text: String, duration: Double = 4) {
        self.id = id; self.text = text; self.duration = duration
    }
}

public struct Surface: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: SurfaceKind
    public var title: String
    public var initialView: Presentation
    public var phase: SurfacePhase
    public var compact: CompactContent?
    public var expanded: UINode
    public var peek: PeekContent?
    public var idlePreview: Bool?

    public init(id: String, kind: SurfaceKind, title: String, initialView: Presentation = .compact,
                phase: SurfacePhase = .active, compact: CompactContent? = nil, expanded: UINode, peek: PeekContent? = nil, idlePreview: Bool? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.initialView = initialView
        self.phase = phase; self.compact = compact; self.expanded = expanded; self.peek = peek; self.idlePreview = idlePreview
    }
}

public struct Snapshot: Codable, Sendable {
    public var protocolVersion: Int
    public var type: String
    public var extensionID: String
    public var revision: Int
    public var surfaces: [Surface]
    public init(extensionID: String, revision: Int, surfaces: [Surface]) {
        self.protocolVersion = 1; self.type = "snapshot"; self.extensionID = extensionID
        self.revision = revision; self.surfaces = surfaces
    }

    public func validate(expectedExtensionID: String) throws {
        guard protocolVersion == 1, type == "snapshot", extensionID == expectedExtensionID, revision > 0,
              surfaces.count <= 16, Set(surfaces.map(\.id)).count == surfaces.count else {
            throw ProtocolError.invalid("Invalid snapshot envelope")
        }
        var count = 0
        var identifiers = Set<String>()
        func visit(_ node: UINode, depth: Int, compact: Bool = false) throws {
            count += 1
            guard depth <= 16, count <= 512, !node.id.isEmpty, node.id.count <= 128,
                  identifiers.insert(node.id).inserted,
                  (node.props.text?.count ?? 0) <= 4096,
                  (node.props.action?.count ?? 0) <= 128 else {
                throw ProtocolError.invalid("Invalid or oversized UI tree")
            }
            if compact && (node.type == .button || node.type == .textField || node.type == .player) {
                throw ProtocolError.invalid("Compact content cannot contain interactive controls")
            }
            if let source = node.props.source, !NowPlayingState.isArtworkSource(source) {
                throw ProtocolError.invalid("Artwork must use an approved artwork CDN or bounded image data")
            }
            if let media = node.props.media { try media.validate() }
            if node.type == .player, node.props.media == nil {
                throw ProtocolError.invalid("A music player requires now-playing state")
            }
            if let value = node.props.value, !value.isFinite || !(0...1).contains(value) {
                throw ProtocolError.invalid("Progress must be between zero and one")
            }
            for child in node.children { try visit(child, depth: depth + 1, compact: compact) }
        }
        for surface in surfaces {
            guard !surface.id.isEmpty, surface.id.count <= 128, !surface.title.isEmpty, surface.title.count <= 128,
                  surface.compact != nil || surface.initialView == .expanded,
                  surface.kind == .prompt ? surface.phase == .pending : surface.phase != .pending else {
                throw ProtocolError.invalid("Invalid surface contract")
            }
            if surface.idlePreview == true, surface.kind != .activity || surface.compact == nil {
                throw ProtocolError.invalid("Idle previews require an activity with compact content")
            }
            if let peek = surface.peek {
                guard surface.kind == .activity, surface.compact != nil,
                      !peek.id.isEmpty, peek.id.count <= 128, !peek.text.isEmpty, peek.text.count <= 256,
                      peek.duration.isFinite, (1...10).contains(peek.duration) else {
                    throw ProtocolError.invalid("A peek requires an activity with compact content, an event id, text, and a duration of 1–10 seconds")
                }
            }
            try visit(surface.expanded, depth: 0)
            for node in (surface.compact?.leading ?? []) + (surface.compact?.trailing ?? []) {
                try visit(node, depth: 0, compact: true)
            }
        }
    }
}

public struct UserEvent: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "event"
    public var action: String
    public var value: String?
    public init(action: String, value: String? = nil) { self.action = action; self.value = value }
}

public struct RuntimeNotice: Codable, Sendable {
    public var protocolVersion = 1
    public var type: String
    public var extensionID: String
    public var message: String
    public init(type: String, extensionID: String, message: String) {
        self.type = type; self.extensionID = extensionID; self.message = String(message.prefix(4096))
    }
}

public struct ExtensionManifest: Codable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var apiVersion: Int
    public var entry: String
    public var permissions: [String]
    public func validate() throws {
        guard id.range(of: "^[a-z][a-z0-9.-]{2,79}$", options: .regularExpression) != nil,
              !name.isEmpty, apiVersion == 1, entry == "bundle.js", Set(permissions).count == permissions.count,
              permissions.allSatisfy({ $0 == "media" }) else {
            throw ProtocolError.invalid("Only API v1 bundles with the optional media permission are supported")
        }
    }
}

public enum ProtocolError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
