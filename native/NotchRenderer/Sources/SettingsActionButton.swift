import SwiftUI
import NotchProtocol

struct SettingsActionButton: View {
    let node: UINode
    let onEvent: (String, String?) -> Void
    var body: some View {
        Group {
            if node.props.tone == .accent {
                Button(node.props.text ?? "Continue", action: send).buttonStyle(.borderedProminent)
            } else {
                Button(node.props.text ?? "Continue", action: send).buttonStyle(.bordered)
            }
        }.controlSize(.regular).disabled(node.props.disabled ?? false)
    }
    private func send() { if let action = node.props.action { onEvent(action, nil) } }
}
