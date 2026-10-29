import SwiftUI

struct ManagementSidebarIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}
