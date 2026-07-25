import SwiftUI

struct AreaMatrixThemeToggleButton: View {
    @Binding var themeOverride: ColorScheme?

    @Environment(\.colorScheme) private var colorScheme
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
            AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
        }
    }

    private var effectiveScheme: ColorScheme {
        themeOverride ?? colorScheme
    }

    private func toggleTheme() {
        withAnimation(.areaMatrixThemeToggle) {
            AppPlatformServices.interactionFeedback.performHaptic(.alignment)
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
        let preference: AppAppearancePreference = switch themeOverride {
        case .dark: .dark
        case .light: .light
        default: .system
        }
        AppPlatformServices.interactionFeedback.applyAppearance(preference)
    }
}

struct AreaMatrixPrimaryGlowButton<Label: View>: View {
    let accent: Color
    var cornerRadius: CGFloat = 8
    let isHovered: Bool
    @Binding var shimmerPhase: CGFloat
    @ViewBuilder let label: () -> Label

    @State private var isGlowing = false

    var body: some View {
        label()
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .shadow(color: .white.opacity(0.15), radius: 0, y: 0.5)
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .background(background)
            .cornerRadius(cornerRadius)
            .areaMatrixPulseAura(
                color: accent,
                duration: AreaMatrixMotionTokens.Duration.pulseAura,
                maxScale: AreaMatrixMotionTokens.Intensity.pulseAuraCTAMaxScale,
                cornerRadius: cornerRadius
            )
            .shadow(
                color: accent.opacity(isHovered ? 0.7 : (isGlowing ? 0.6 : 0.3)),
                radius: isHovered ? 20 : (isGlowing ? 16 : 6),
                y: isHovered ? 6 : 4
            )
            .scaleEffect(isHovered ? AreaMatrixMotionTokens.Intensity.hoverScale : 1.0)
            .offset(y: isHovered ? -2 : 0)
            .animation(.areaMatrixQuickFade, value: isHovered)
            .areaMatrixMagneticHover(intensity: AreaMatrixMotionTokens.Intensity.magneticCTA)
            .onAppear {
                withAnimation(.areaMatrixGlowBreath) {
                    isGlowing = true
                }
                withAnimation(
                    .linear(duration: AreaMatrixMotionTokens.Duration.shimmerSweep)
                        .repeatForever(autoreverses: false)
                        .delay(1)
                ) {
                    shimmerPhase = 1.5
                }
            }
    }

    private var background: some View {
        ZStack {
            AreaMatrixTheme.Gradients.primaryAction(accent: accent)

            LinearGradient(
                colors: [.clear, .white.opacity(0.4), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .offset(x: shimmerPhase * 200)
            .mask(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

struct AreaMatrixLinkActionLabel: View {
    let title: String
    let iconName: String
    var trailingIconName = "arrow.up.right"
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            underlinedTitle
            slidingTrailingIcon
        }
        .font(.system(size: 13))
        .foregroundColor(isHovered ? .primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
        )
        .animation(.areaMatrixQuickFade, value: isHovered)
        .contentShape(Rectangle())
    }

    private var underlinedTitle: some View {
        Text(title)
            .background(
                Rectangle()
                    .frame(height: 1)
                    .offset(y: 2)
                    .opacity(isHovered ? 1 : 0),
                alignment: .bottom
            )
    }

    private var slidingTrailingIcon: some View {
        ZStack {
            Image(systemName: trailingIconName)
                .opacity(isHovered ? 0 : 0.6)
                .offset(x: isHovered ? 10 : 0, y: isHovered ? -10 : 0)
            Image(systemName: trailingIconName)
                .opacity(isHovered ? 0.6 : 0)
                .offset(x: isHovered ? 0 : -10, y: isHovered ? 10 : 0)
        }
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 12, height: 12)
        .clipped()
    }
}

struct AreaMatrixPrimaryActionLabel: View {
    let title: String
    let iconName: String
    let shortcut: String?
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Color.clear
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: iconName)
                        .symbolEffect(.bounce, value: isHovered)
                )
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.leading, 4)
            }
        }
    }
}

struct AreaMatrixPrimaryButtonStyle: ButtonStyle {
    var accent: Color = AreaMatrixTheme.Colors.tealBright
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                AreaMatrixTheme.Gradients.primaryAction(accent: accent)
                    .opacity(configuration.isPressed ? 0.85 : (isHovered ? 1.0 : 0.95))
            )
            .foregroundStyle(.black)
            .clipShape(Capsule())
            .shadow(color: accent.opacity(isHovered ? 0.55 : 0.3), radius: isHovered ? 12 : 6, y: 3)
            .scaleEffect(
                configuration.isPressed
                    ? AreaMatrixMotionTokens.Intensity.pressScale
                    : (isHovered ? 1.02 : 1.0)
            )
            .animation(.areaMatrixQuickFade, value: configuration.isPressed)
            .animation(.areaMatrixQuickFade, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
            }
    }
}

struct AreaMatrixSecondaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0.0)))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? AreaMatrixMotionTokens.Intensity.pressScale : 1.0)
            .animation(.areaMatrixQuickFade, value: configuration.isPressed)
            .animation(.areaMatrixQuickFade, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
            }
    }
}
