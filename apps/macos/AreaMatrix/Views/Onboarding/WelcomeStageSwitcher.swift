import SwiftUI

struct WelcomeStageSwitcher: View {
    let stage: WelcomeStage
    let parallax: WelcomeParallax

    var body: some View {
        ZStack {
            ForEach(WelcomeStage.allCases, id: \.self) { candidateStage in
                stageContent(candidateStage)
                    .allowsHitTesting(candidateStage == stage)
                    .environment(
                        \.areaMatrixStagePhase,
                        candidateStage == stage ? .enter(isVisible: true) : .exit(isVisible: false)
                    )
                    .environment(
                        \.areaMatrixStageParallax,
                        candidateStage == stage ? parallax.areaMatrixParallax : .zero
                    )
                    .zIndex(candidateStage == stage ? 2 : 1)
            }
        }
    }

    @ViewBuilder
    private func stageContent(_ stage: WelcomeStage) -> some View {
        switch stage {
        case .default: StageDefaultView()
        case .feat1: StageClassifyView()
        case .feat2: StageSecurityView()
        case .feat3: StageTrackingView()
        case .feat4: StageHelpView()
        case .feat5: StageStartView()
        }
    }
}

extension EnvironmentValues {
    var welcomeStagePhase: AreaMatrixStagePhase {
        get { areaMatrixStagePhase }
        set { areaMatrixStagePhase = newValue }
    }

    var welcomeStageParallax: WelcomeParallax {
        get {
            let parallax = areaMatrixStageParallax
            return WelcomeParallax(horizontal: parallax.horizontal, vertical: parallax.vertical)
        }
        set { areaMatrixStageParallax = newValue.areaMatrixParallax }
    }
}

extension View {
    func welcomeStageVisualMotion() -> some View {
        areaMatrixStageVisualMotion()
    }

    func welcomeStageTextMotion(delay: Double) -> some View {
        areaMatrixStageTextMotion(delay: delay)
    }
}
