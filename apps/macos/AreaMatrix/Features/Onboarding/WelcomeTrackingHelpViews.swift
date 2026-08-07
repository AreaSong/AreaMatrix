import AreaMatrixUIFoundation
import SwiftUI

struct WelcomeTrackingSceneView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixTimelineDiorama()
                .areaMatrixSceneVisualMotion()
            AreaMatrixSceneText(
                title: L10n.string("onboarding.welcome.tracking.title"),
                description: L10n.string("onboarding.welcome.tracking.description"),
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.coral : AreaMatrixTheme.Colors.coralDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.goldDeep
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

struct WelcomeHelpSceneView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixSceneParallax) private var parallax

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixWorkflowDiorama()
                .areaMatrixSceneVisualMotion()
                .offset(x: parallax.horizontal * 10, y: parallax.vertical * 10)
            AreaMatrixSceneText(
                title: L10n.string("onboarding.welcome.help.title"),
                description: L10n.string("onboarding.welcome.help.description"),
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.purple : AreaMatrixTheme.Colors.purpleDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.emerald : AreaMatrixTheme.Colors.emeraldDeep
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}
