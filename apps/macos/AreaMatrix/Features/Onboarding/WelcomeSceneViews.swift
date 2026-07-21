import SwiftUI

enum WelcomeScene: Int, CaseIterable {
    case `default` = 0
    case feat1
    case feat2
    case feat3
    case feat4
    case feat5

    var ambientScene: AreaMatrixAmbientScene {
        switch self {
        case .default: .home
        case .feat1: .classify
        case .feat2: .security
        case .feat3: .tracking
        case .feat4: .help
        case .feat5: .start
        }
    }

    var accentColor: Color {
        ambientScene.accent.color
    }
}

// MARK: - Default Intro

struct WelcomeDefaultSceneView: View {
    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixLaunchBrandVisual()

            AreaMatrixLaunchCopyText(
                title: String(localized: "onboarding.welcome.default.title"),
                description: String(localized: "onboarding.welcome.default.description")
            )
        }
    }
}

// MARK: - Start CTA

struct WelcomeStartSceneView: View {
    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixFolderLaunchVisual()

            AreaMatrixSceneText(
                title: String(localized: "onboarding.welcome.start.title"),
                description: String(localized: "onboarding.welcome.start.description")
            )
        }
    }
}
