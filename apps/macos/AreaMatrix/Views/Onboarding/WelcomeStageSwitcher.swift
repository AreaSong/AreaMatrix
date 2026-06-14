import SwiftUI

struct WelcomeStageSwitcher: View {
    let stage: WelcomeStage
    let parallax: WelcomeParallax

    var body: some View {
        ZStack {
            ForEach(WelcomeStage.allCases, id: \.self) { s in
                stageContent(s)
                    .allowsHitTesting(s == stage)
                    .environment(\.welcomeStagePhase, s == stage ? .enter(isVisible: true) : .exit(isVisible: false))
                    .environment(\.welcomeStageParallax, s == stage ? parallax : .zero)
                    .zIndex(s == stage ? 2 : 1)
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

enum WelcomeStagePhase: Equatable {
    case enter(isVisible: Bool)
    case exit(isVisible: Bool)

    var isVisible: Bool {
        switch self {
        case let .enter(isVisible), let .exit(isVisible):
            isVisible
        }
    }
}

private struct WelcomeStagePhaseKey: EnvironmentKey {
    static let defaultValue = WelcomeStagePhase.enter(isVisible: true)
}

private struct WelcomeStageParallaxKey: EnvironmentKey {
    static let defaultValue = WelcomeParallax.zero
}

extension EnvironmentValues {
    var welcomeStagePhase: WelcomeStagePhase {
        get { self[WelcomeStagePhaseKey.self] }
        set { self[WelcomeStagePhaseKey.self] = newValue }
    }

    var welcomeStageParallax: WelcomeParallax {
        get { self[WelcomeStageParallaxKey.self] }
        set { self[WelcomeStageParallaxKey.self] = newValue }
    }
}

struct WelcomeStageVisualMotion: ViewModifier {
    @Environment(\.welcomeStagePhase) private var stagePhase
    @Environment(\.welcomeStageParallax) private var parallax

    func body(content: Content) -> some View {
        content
            .opacity(stagePhase.isVisible ? 1 : 0)
            .offset(y: stagePhase.isVisible ? 0 : verticalOffset)
            .scaleEffect(stagePhase.isVisible ? 1 : scale)
            .rotation3DEffect(
                .degrees(parallax.vertical * -12),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.75
            )
            .rotation3DEffect(
                .degrees(parallax.horizontal * 12),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.75
            )
            .animation(animation, value: stagePhase)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16), value: parallax)
    }

    private var verticalOffset: CGFloat {
        switch stagePhase {
        case .enter: return 12  // 从下方轻微滑入
        case .exit: return -8   // 向上方轻微滑出
        }
    }

    private var scale: CGFloat {
        switch stagePhase {
        case .enter: return 0.94 // Start smaller, expand to 1.0
        case .exit: return 1.06 // Expand outwards while fading
        }
    }

    private var animation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
    }
}

struct WelcomeStageTextMotion: ViewModifier {
    let delay: Double
    @Environment(\.welcomeStagePhase) private var stagePhase

    func body(content: Content) -> some View {
        content
            .opacity(stagePhase.isVisible ? 1 : 0)
            .scaleEffect(stagePhase.isVisible ? 1 : scale)
            .animation(animation, value: stagePhase)
    }

    private var scale: CGFloat {
        switch stagePhase {
        case .enter: return 0.97 // Text starts slightly smaller
        case .exit: return 1.03 // Text expands slightly outwards
        }
    }

    private var animation: Animation {
        switch stagePhase {
        case .enter: return .timingCurve(0.16, 1, 0.3, 1, duration: 0.6).delay(delay)
        case .exit: return .timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
        }
    }
}

extension View {
    func welcomeStageVisualMotion() -> some View {
        modifier(WelcomeStageVisualMotion())
    }

    func welcomeStageTextMotion(delay: Double) -> some View {
        modifier(WelcomeStageTextMotion(delay: delay))
    }
}
