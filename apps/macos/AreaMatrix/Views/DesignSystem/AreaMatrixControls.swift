import AreaMatrixUIFoundation
import SwiftUI

typealias AreaMatrixPrimaryGlowButton<Label: View> = AreaMatrixUIFoundation.AreaMatrixPrimaryGlowButton<Label>
typealias AreaMatrixLinkActionLabel = AreaMatrixUIFoundation.AreaMatrixLinkActionLabel
typealias AreaMatrixPrimaryActionLabel = AreaMatrixUIFoundation.AreaMatrixPrimaryActionLabel
typealias AreaMatrixPrimaryButtonStyle = AreaMatrixUIFoundation.AreaMatrixPrimaryButtonStyle
typealias AreaMatrixSecondaryButtonStyle = AreaMatrixUIFoundation.AreaMatrixSecondaryButtonStyle

struct AreaMatrixThemeToggleButton: View {
    @Binding var themeOverride: ColorScheme?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var isHovered = false
    @State private var spin: Double = 0

    var body: some View {
        Button {
            toggleTheme()
        } label: {
            Image(systemName: effectiveScheme == .dark ? "sun.max" : "moon")
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? .secondary : .tertiary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .rotationEffect(.degrees(spin))
                .contentTransition(.symbolEffect(.replace))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.string("切换明暗模式"))
        .animation(.areaMatrixQuickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            interactionFeedback.setPointingCursor(active: hovering)
        }
    }

    private var effectiveScheme: ColorScheme {
        themeOverride ?? colorScheme
    }

    private func toggleTheme() {
        withAnimation(.areaMatrixThemeToggle) {
            interactionFeedback.performHaptic(.alignment)
            if themeOverride == nil {
                themeOverride = colorScheme == .dark ? .light : .dark
            } else {
                themeOverride = themeOverride == .dark ? .light : .dark
            }
            applyAppAppearance()
        }

        withAnimation(
            .spring(
                response: AreaMatrixMotionTokens.Spring.themeSpinResponse,
                dampingFraction: AreaMatrixMotionTokens.Spring.themeSpinDamping
            )
        ) {
            spin += 360
        }
    }

    private func applyAppAppearance() {
        let preference: AreaMatrixAppearancePreference = switch themeOverride {
        case .dark: .dark
        case .light: .light
        default: .system
        }
        interactionFeedback.applyAppearance(preference)
    }
}
