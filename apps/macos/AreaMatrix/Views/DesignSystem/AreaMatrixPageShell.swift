import SwiftUI

/// Shared page chrome: glass content panels, empty states, and workspace region shells.
struct AreaMatrixGlassContentPanelModifier: ViewModifier {
    var width: CGFloat? = 580
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 40

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
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

struct AreaMatrixEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var accent: Color = AreaMatrixTheme.Colors.tealBright
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var entered = false
    @State private var isPrimaryHovered = false
    @State private var shimmerPhase: CGFloat = -1.5

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Image(systemName: systemImage)
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(accent)
                    .blur(radius: 20)
                    .opacity(0.45)
                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(accent)
            }
            .areaMatrixDelayedEntrance(isVisible: entered, delay: AreaMatrixMotionTokens.EntranceDelay.header)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .areaMatrixDelayedEntrance(isVisible: entered, delay: AreaMatrixMotionTokens.EntranceDelay.body)

            HStack(spacing: 12) {
                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                    }
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
                }
                if let primaryTitle, let primaryAction {
                    Button(action: primaryAction) {
                        AreaMatrixPrimaryGlowButton(
                            accent: accent,
                            isHovered: isPrimaryHovered,
                            shimmerPhase: $shimmerPhase
                        ) {
                            AreaMatrixPrimaryActionLabel(
                                title: primaryTitle,
                                iconName: "plus",
                                shortcut: nil,
                                isHovered: isPrimaryHovered
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isPrimaryHovered = hovering
                        interactionFeedback.setPointingCursor(active: hovering)
                    }
                }
            }
            .areaMatrixDelayedEntrance(isVisible: entered, delay: AreaMatrixMotionTokens.EntranceDelay.footer)
        }
        .areaMatrixGlassContentPanel(width: 520)
        .onAppear { entered = true }
    }
}

struct AreaMatrixWorkspaceRegionShellModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
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

struct AreaMatrixPageContentEntranceModifier: ViewModifier {
    @State private var entered = false
    var delay: Double = AreaMatrixMotionTokens.EntranceDelay.body

    func body(content: Content) -> some View {
        content
            .areaMatrixDelayedEntrance(isVisible: entered, delay: delay)
            .onAppear { entered = true }
    }
}

extension View {
    func areaMatrixGlassContentPanel(width: CGFloat? = 580, cornerRadius: CGFloat = 24,
                                     padding: CGFloat = 40) -> some View {
        modifier(AreaMatrixGlassContentPanelModifier(width: width, cornerRadius: cornerRadius, padding: padding))
    }

    func areaMatrixWorkspaceRegionShell(cornerRadius: CGFloat = 12) -> some View {
        modifier(AreaMatrixWorkspaceRegionShellModifier(cornerRadius: cornerRadius))
    }

    func areaMatrixPageContentEntrance(delay: Double = AreaMatrixMotionTokens.EntranceDelay.body) -> some View {
        modifier(AreaMatrixPageContentEntranceModifier(delay: delay))
    }
}
