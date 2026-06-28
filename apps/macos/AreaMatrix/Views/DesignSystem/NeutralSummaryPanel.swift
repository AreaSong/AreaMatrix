import SwiftUI

struct NeutralSummaryPanel<Content: View>: View {
    var contentPadding: CGFloat = 10
    var cornerRadius: CGFloat = 8
    var backgroundOpacity: Double = 0.10
    private let content: Content

    init(
        contentPadding: CGFloat = 10,
        cornerRadius: CGFloat = 8,
        backgroundOpacity: Double = 0.10,
        @ViewBuilder content: () -> Content
    ) {
        self.contentPadding = contentPadding
        self.cornerRadius = cornerRadius
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(Color.secondary.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
