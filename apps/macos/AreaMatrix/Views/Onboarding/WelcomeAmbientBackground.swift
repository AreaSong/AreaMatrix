import SwiftUI

struct WelcomeAmbientBackground: View {
    let stage: WelcomeStage
    let parallax: WelcomeParallax

    var body: some View {
        AreaMatrixAmbientBackground(
            scene: stage.ambientScene,
            parallax: parallax.areaMatrixParallax
        )
    }
}

private extension WelcomeStage {
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
}
