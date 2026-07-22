import SwiftUI

struct WelcomeTitlebar: View {
    @Binding var themeOverride: ColorScheme?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Text("AreaMatrix")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                AreaMatrixThemeToggleButton(themeOverride: $themeOverride)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
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
                icon: "arrow.down.doc",
                title: L10n.string("onboarding.welcome.feature.classify.title"),
                description: L10n.string("onboarding.welcome.feature.classify.description"),
                accentColor: AreaMatrixTheme.Colors.tealBright,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard1
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat2,
                icon: "checkmark.shield",
                title: L10n.string("onboarding.welcome.feature.safety.title"),
                description: L10n.string("onboarding.welcome.feature.safety.description"),
                accentColor: AreaMatrixTheme.Colors.gold,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard2
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat3,
                icon: "rectangle.split.2x1",
                title: L10n.string("onboarding.welcome.feature.overview.title"),
                description: L10n.string("onboarding.welcome.feature.overview.description"),
                accentColor: AreaMatrixTheme.Colors.coral,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard3
            )
        ]
    }
}
