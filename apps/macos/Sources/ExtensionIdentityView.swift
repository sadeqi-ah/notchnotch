import SwiftUI
import NotchProtocol

struct ExtensionIdentityView: View {
    let manifest: ExtensionManifest
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: manifest.icon ?? "puzzlepiece.extension")
            .font(.system(size: size * 0.58))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.tint, in: RoundedRectangle(cornerRadius: size * 0.2))
            .accessibilityHidden(true)
    }
}
