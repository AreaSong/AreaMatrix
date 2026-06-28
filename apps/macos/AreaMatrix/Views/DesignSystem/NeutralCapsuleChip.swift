import SwiftUI

struct NeutralCapsuleChip<Content: View>: View {
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 3
    var backgroundOpacity: Double = 0.12
    private let content: Content

    init(
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 3,
        backgroundOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Color.secondary.opacity(backgroundOpacity), in: Capsule())
    }
}
