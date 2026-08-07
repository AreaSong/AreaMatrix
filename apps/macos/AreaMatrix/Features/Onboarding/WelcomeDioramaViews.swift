import AreaMatrixUIFoundation
import SwiftUI

struct WelcomeClassifySceneView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixClassificationDiorama()
                .areaMatrixSceneVisualMotion()
            AreaMatrixSceneText(
                title: L10n.string("onboarding.welcome.classify.title"),
                description: L10n.string("onboarding.welcome.classify.description"),
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors.emeraldDeep
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

struct WelcomeSecuritySceneView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixProtectionDiorama()
                .areaMatrixSceneVisualMotion()
            AreaMatrixSceneText(
                title: L10n.string("onboarding.welcome.security.title"),
                description: L10n.string("onboarding.welcome.security.description"),
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.goldDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.coral : AreaMatrixTheme.Colors.coralDeep
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
