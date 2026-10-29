import SwiftUI
import NotchProtocol

/// The management-window presentation of the same validated extension UI tree.
/// System colors and native controls keep setup readable in both appearances.
public struct SettingsNodeView: View {
    public let node: UINode
    public let onEvent: (String, String?) -> Void
    public init(node: UINode, onEvent: @escaping (String, String?) -> Void) {
        self.node = node; self.onEvent = onEvent
    }
    public var body: some View { content }

    @ViewBuilder private var content: some View {
        switch node.type {
        case .column:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(node.children) { SettingsNodeView(node: $0, onEvent: onEvent) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        case .row:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { ForEach(node.children) { SettingsNodeView(node: $0, onEvent: onEvent) } }.fixedSize()
                VStack(alignment: .leading, spacing: 10) { ForEach(node.children) { SettingsNodeView(node: $0, onEvent: onEvent) } }
            }
        case .text:
            Text(node.props.text ?? "").font(node.props.size == .title ? .headline : node.props.size == .caption ? .caption : .body)
                .foregroundStyle(color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        case .symbol:
            Image(systemName: node.props.name ?? "circle").foregroundStyle(color)
        case .progress:
            ProgressView(value: node.props.value ?? 0)
        case .button:
            SettingsActionButton(node: node, onEvent: onEvent)
        case .textField:
            SettingsTextField(node: node, onEvent: onEvent)
        case .artwork, .waveform, .player:
            EmptyView() // Excluded by the settings contract before rendering.
        }
    }
    private var color: Color {
        switch node.props.tone {
        case .secondary: .secondary
        case .accent: .accentColor
        case .success: .green
        case .warning: .orange
        default: .primary
        }
    }
}
