import SwiftUI
import NotchProtocol

struct SettingsTextField: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    @State private var text = ""
    @FocusState private var editing: Bool
    var body: some View {
        TextField(node.props.placeholder ?? "", text: $text)
            .textFieldStyle(.roundedBorder).focused($editing)
            .disabled(node.props.disabled ?? false)
            .onAppear { text = node.props.text ?? "" }
            .onChange(of: node.props.text) { _, value in
                if !editing, text != value { text = value ?? "" }
            }
            .onChange(of: text) { _, value in
                if editing, value != node.props.text, let action = node.props.action {
                    onEvent(action, String(value.prefix(4096)))
                }
            }
    }
}
