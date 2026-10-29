import SwiftUI

struct ManagementNotice: View {
    let text: String
    var isError = false
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green).accessibilityHidden(true)
            Text(text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly)
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(4)
            }
        }.accessibilityElement(children: .contain)
    }
}
