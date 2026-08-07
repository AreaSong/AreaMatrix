import AreaMatrixUIFoundation
import SwiftUI

struct WelcomeTitlebar: View {
    @Binding var themeOverride: ColorScheme?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Text(L10n.string("AreaMatrix"))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                Spacer()
                WelcomeLanguageCycleButton()
                AreaMatrixThemeToggleButton(themeOverride: $themeOverride)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
    }
}

private struct WelcomeLanguageCycleButton: View {
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var localizer: AppLocalizer
    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var isHovered = false

    var body: some View {
        Button(action: languageStore.selectNext) {
            languageIndicator
                .foregroundStyle(isHovered ? .secondary : .tertiary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
                .scaleEffect(isHovered ? 1.15 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(L10n.string("settings.language.interface.title"))
        .accessibilityValue(currentLanguageName)
        .accessibilityHint(L10n.format("onboarding.welcome.language.hint", nextLanguageName))
        .accessibilityIdentifier("welcome-interface-language-cycle")
        .animation(.areaMatrixQuickFade, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            interactionFeedback.setPointingCursor(active: hovering)
        }
    }

    @ViewBuilder
    private var languageIndicator: some View {
        switch languageStore.selection {
        case .system:
            Image(systemName: "globe")
                .font(.system(size: 12))
        case .zhHans:
            Text(localizer.resolve(L10n.verbatim("中", reason: .languageGlyph)))
                .font(.system(size: 12, weight: .semibold))
        case .en:
            Text(localizer.resolve(L10n.verbatim("EN", reason: .languageGlyph)))
                .font(.system(size: 9, weight: .bold))
        }
    }

    private var currentLanguageName: String {
        localizer.resolve(languageStore.selection.displayMessage)
    }

    private var nextLanguageName: String {
        localizer.resolve(languageStore.selection.next.displayMessage)
    }

    private var helpText: String {
        L10n.format("onboarding.welcome.language.help", currentLanguageName, nextLanguageName)
    }
}

struct WelcomeFeatureCardsGrid: View {
    let activeID: WelcomeScene?
    let onHoverChanged: (WelcomeScene, Bool) -> Void

    var body: some View {
        AreaMatrixFeatureCardGroup(
            cards: featureCards,
            activeID: activeID,
            onHoverChanged: onHoverChanged
        )
    }

    private var featureCards: [AreaMatrixFeatureCardSpec<WelcomeScene>] {
        [
            AreaMatrixFeatureCardSpec(
                id: .feat1,
                icon: .files,
                title: L10n.string("onboarding.welcome.feature.classify.title"),
                description: L10n.string("onboarding.welcome.feature.classify.description"),
                accentColor: AreaMatrixTheme.Colors.tealBright,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard1
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat2,
                icon: .shieldCheck,
                title: L10n.string("onboarding.welcome.feature.safety.title"),
                description: L10n.string("onboarding.welcome.feature.safety.description"),
                accentColor: AreaMatrixTheme.Colors.gold,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard2
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat3,
                icon: .globe,
                title: L10n.string("onboarding.welcome.feature.overview.title"),
                description: L10n.string("onboarding.welcome.feature.overview.description"),
                accentColor: AreaMatrixTheme.Colors.coral,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard3
            )
        ]
    }
}
