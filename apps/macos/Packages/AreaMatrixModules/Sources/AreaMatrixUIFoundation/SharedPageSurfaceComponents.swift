import SwiftUI

/// Glass surface used by centered pages and full-width feature content.
///
/// The modifier only owns visual surface treatment. Width, padding and
/// content remain caller-controlled so feature pages can share the surface
/// without sharing business state or navigation.
public struct AreaMatrixGlassContentPanelModifier: ViewModifier {
    public var width: CGFloat?
    public var cornerRadius: CGFloat
    public var padding: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(width: CGFloat? = 580, cornerRadius: CGFloat = 24, padding: CGFloat = 40) {
        self.width = width
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.4))
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 50, y: 25)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.3 : 0.7),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .modifier(AreaMatrixOptionalFixedWidthModifier(width: width))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AreaMatrixOptionalFixedWidthModifier: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width)
        } else {
            content
        }
    }
}

/// Low-contrast shell for a workspace region such as a list or settings pane.
public struct AreaMatrixWorkspaceRegionShellModifier: ViewModifier {
    public var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

public extension View {
    func areaMatrixGlassContentPanel(
        width: CGFloat? = 580,
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 40
    ) -> some View {
        modifier(
            AreaMatrixGlassContentPanelModifier(
                width: width,
                cornerRadius: cornerRadius,
                padding: padding
            )
        )
    }

    func areaMatrixWorkspaceRegionShell(cornerRadius: CGFloat = 12) -> some View {
        modifier(AreaMatrixWorkspaceRegionShellModifier(cornerRadius: cornerRadius))
    }
}
