import SwiftUI

/// Capsule action button used by step-like feature pages.
public struct AreaMatrixCapsuleButton<Label: View>: View {
    public var accent: Color
    public let isHovered: Bool
    private let action: () -> Void
    private let label: () -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        accent: Color = AreaMatrixTheme.Colors.teal,
        isHovered: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.accent = accent
        self.isHovered = isHovered
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    AreaMatrixTheme.Gradients.primaryAction(accent: accent)
                        .opacity(isHovered ? 1 : 0.9)
                )
                .foregroundStyle(.black)
                .clipShape(Capsule())
                .shadow(
                    color: accent.opacity(isHovered ? 0.5 : 0.2),
                    radius: isHovered ? 16 : 8,
                    y: isHovered ? 8 : 4
                )
                .scaleEffect(isHovered ? 1.02 : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(
                            response: AreaMatrixMotionTokens.Spring.hoverResponse,
                            dampingFraction: AreaMatrixMotionTokens.Spring.hoverDamping
                        ),
                    value: isHovered
                )
        }
        .buttonStyle(.plain)
    }
}

/// Quiet capsule action button used for secondary step-page actions.
public struct AreaMatrixGhostButton<Label: View>: View {
    public let isHovered: Bool
    private let action: () -> Void
    private let label: () -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isHovered: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isHovered = isHovered
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .background(Color.primary.opacity(isHovered ? 0.08 : 0), in: Capsule())
                .animation(
                    reduceMotion ? nil : .easeOut(duration: AreaMatrixMotionTokens.Duration.quickFade),
                    value: isHovered
                )
        }
        .buttonStyle(.plain)
    }
}
