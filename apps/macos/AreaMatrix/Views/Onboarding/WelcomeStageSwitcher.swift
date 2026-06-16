import SwiftUI

struct WelcomeStageSwitcher: View {
    let stage: WelcomeStage
    let parallax: AreaMatrixParallax

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
                        candidateStage == stage ? parallax : .zero
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
