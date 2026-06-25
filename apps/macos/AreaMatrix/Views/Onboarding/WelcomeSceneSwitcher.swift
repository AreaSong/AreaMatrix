import SwiftUI

struct WelcomeSceneSwitcher: View {
    let scene: WelcomeScene
    let parallax: AreaMatrixParallax

    var body: some View {
        ZStack {
            ForEach(WelcomeScene.allCases, id: \.self) { candidateScene in
                sceneContent(candidateScene)
                    .allowsHitTesting(candidateScene == scene)
                    .environment(
                        \.areaMatrixSceneVisibility,
                        candidateScene == scene ? .enter(isVisible: true) : .exit(isVisible: false)
                    )
                    .environment(
                        \.areaMatrixSceneParallax,
                        candidateScene == scene ? parallax : .zero
                    )
                    .zIndex(candidateScene == scene ? 2 : 1)
            }
        }
    }

    @ViewBuilder
    private func sceneContent(_ scene: WelcomeScene) -> some View {
        switch scene {
        case .default: WelcomeDefaultSceneView()
        case .feat1: WelcomeClassifySceneView()
        case .feat2: WelcomeSecuritySceneView()
        case .feat3: WelcomeTrackingSceneView()
        case .feat4: WelcomeHelpSceneView()
        case .feat5: WelcomeStartSceneView()
        }
    }
}
