import SwiftUI

struct TintedStatusBanner<Content: View>: View {
    let tint: Color
    let cornerRadius: CGFloat
    let fillsWidth: Bool
    let contentPadding: CGFloat
    let backgroundOpacity: Double
    private let content: Content

    init(
        tint: Color,
        cornerRadius: CGFloat = 8,
        fillsWidth: Bool = true,
        contentPadding: CGFloat = 12,
        backgroundOpacity: Double = 0.08,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.fillsWidth = fillsWidth
        self.contentPadding = contentPadding
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .background(tint.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct TintedOutlinedStatusBanner<Content: View>: View {
    let tint: Color
    let cornerRadius: CGFloat
    private let content: Content

    init(
        tint: Color,
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(tint.opacity(0.15), lineWidth: 1))
    }
}
