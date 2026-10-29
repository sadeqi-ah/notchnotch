import SwiftUI
import NotchProtocol

public enum NotchPalette {
    public static let accent = Color.white
    public static func color(_ tone: Tone?) -> Color {
        switch tone {
        case .secondary: Color.white.opacity(0.53)
        case .accent: accent
        case .success: Color(red: 0.56, green: 0.83, blue: 0.65)
        case .warning: Color(red: 0.98, green: 0.72, blue: 0.40)
        default: .white
        }
    }
}

public struct NativeNodeView: View {
    public let node: UINode
    public let compact: Bool
    public let cameraHeight: CGFloat
    public let onEvent: (String, String?) -> Void
    public init(node: UINode, compact: Bool = false, cameraHeight: CGFloat = 32, onEvent: @escaping (String, String?) -> Void) {
        self.node = node; self.compact = compact; self.cameraHeight = cameraHeight; self.onEvent = onEvent
    }

    public var body: some View {
        content.foregroundStyle(NotchPalette.color(node.props.tone))
    }

    @ViewBuilder private var content: some View {
        switch node.type {
        case .column:
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                ForEach(node.children) { child in
                    NativeNodeView(node: child, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
                }
            }.frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        case .row:
            HStack(spacing: compact ? 6 : 10) {
                ForEach(node.children) { child in
                    NativeNodeView(node: child, compact: compact, cameraHeight: cameraHeight, onEvent: onEvent)
                }
            }
        case .text:
            Text(node.props.text ?? "")
                .font(font)
                .monospacedDigit()
                .tracking(node.props.size == .caption && !compact ? 0.9 : node.props.size == .timer ? -1.4 : 0)
                .lineLimit(compact ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(node.props.text ?? "")
        case .symbol:
            Image(systemName: node.props.name ?? "circle")
                .font(.system(size: 14, weight: .medium))
                .accessibilityHidden(true)
        case .progress:
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(NotchPalette.color(node.props.tone))
                        .frame(width: geometry.size.width * (node.props.value ?? 0))
                }
            }.frame(height: 3)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(Int((node.props.value ?? 0) * 100)) percent")
        case .button:
            Button {
                if let action = node.props.action { onEvent(action, nil) }
            } label: {
                Text(node.props.text ?? "Continue")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 15).frame(height: 29)
                    .foregroundStyle(node.props.tone == .accent ? .black : .white.opacity(0.85))
                    .background(node.props.tone == .accent ? NotchPalette.accent : .white.opacity(0.10), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(NotchPressStyle())
            .disabled(node.props.disabled ?? false)
            .opacity(node.props.disabled == true ? 0.4 : 1)
        case .textField:
            NativeTextField(node: node, onEvent: onEvent)
        case .artwork:
            AlbumArtwork(source: node.props.source, size: compact ? 18 : 60)
        case .waveform:
            PlaybackWaveform(playing: node.props.value == 1, source: node.props.source)
        case .player:
            if let state = node.props.media {
                MusicPlayerView(state: state, cameraHeight: cameraHeight) { request in
                    guard let action = node.props.action,
                          let data = try? JSONEncoder().encode(request),
                          let value = String(data: data, encoding: .utf8) else { return }
                    onEvent(action, value)
                }
            }
        }
    }

    private var font: Font {
        switch node.props.size {
        case .timer: .system(size: 40, weight: .light, design: .rounded)
        case .title: .system(size: 21, weight: .medium)
        case .caption: .system(size: compact ? 10 : 8, weight: .medium)
        default: .system(size: 12, weight: .regular)
        }
    }
}

struct NotchPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct NativeTextField: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    @State private var text = ""
    @FocusState private var isEditing: Bool
    var body: some View {
        TextField(node.props.placeholder ?? "", text: $text)
            .focused($isEditing)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .onAppear { text = node.props.text ?? "" }
            .onChange(of: node.props.text) { _, value in
                // A runner acknowledgement can arrive several keystrokes behind.
                // Never replace an active native edit with an older React render.
                if !isEditing, text != value { text = value ?? "" }
            }
            .onChange(of: text) { _, value in
                if isEditing, value != node.props.text, let action = node.props.action {
                    onEvent(action, String(value.prefix(4096)))
                }
            }
    }
}
