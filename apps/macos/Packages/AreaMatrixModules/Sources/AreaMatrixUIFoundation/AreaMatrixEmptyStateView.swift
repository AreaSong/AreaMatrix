import SwiftUI

/// Shared empty-state surface used by Feature pages and the developer UI catalog.
public struct AreaMatrixEmptyStateView: View {
    public let systemImage: String
    public let title: String
    public let message: String
    public var accent: Color
    public var primaryTitle: String?
    public var primaryAction: (() -> Void)?
    public var secondaryTitle: String?
    public var secondaryAction: (() -> Void)?

    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var entered = false
    @State private var isPrimaryHovered = false
    @State private var shimmerPhase: CGFloat = -1.5

    public init(
        systemImage: String,
        title: String,
        message: String,
        accent: Color = AreaMatrixTheme.Colors.tealBright,
        primaryTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.accent = accent
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
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
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(AreaMatrixSecondaryButtonStyle())
                }
                if let primaryTitle, let primaryAction {
                    primaryButton(title: primaryTitle, action: primaryAction)
                }
            }
            .areaMatrixDelayedEntrance(isVisible: entered, delay: AreaMatrixMotionTokens.EntranceDelay.footer)
        }
        .areaMatrixGlassContentPanel(width: 520)
        .onAppear { entered = true }
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AreaMatrixPrimaryGlowButton(
                accent: accent,
                isHovered: isPrimaryHovered,
                shimmerPhase: $shimmerPhase
            ) {
                AreaMatrixPrimaryActionLabel(
                    title: title,
                    iconName: "plus",
                    shortcut: nil,
                    isHovered: isPrimaryHovered
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isPrimaryHovered = hovering
            MainActor.assumeIsolated {
                interactionFeedback.setPointingCursor(active: hovering)
            }
        }
    }
}
