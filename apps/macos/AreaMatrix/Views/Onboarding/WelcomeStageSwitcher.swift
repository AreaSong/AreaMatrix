import SwiftUI

struct WelcomeStageSwitcher: View {
    let stage: WelcomeStage
    let parallax: WelcomeParallax

    @State private var currentStage: WelcomeStage = .default
    @State private var outgoingStage: WelcomeStage?
    @State private var incomingVisible = true
    @State private var outgoingVisible = false
    @State private var transitionToken = UUID()
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let outgoingStage {
                stageContent(outgoingStage)
                    .id(WelcomeStageLayerID(stage: outgoingStage, token: transitionToken, role: .outgoing))
                    .modifier(WelcomeStageShellMotion(mode: .exit, isVisible: outgoingVisible))
                    .environment(\.welcomeStagePhase, .exit(isVisible: outgoingVisible))
                    .environment(\.welcomeStageParallax, .zero)
                    .zIndex(1)
            }

            stageContent(currentStage)
                .id(WelcomeStageLayerID(stage: currentStage, token: transitionToken, role: .incoming))
                .modifier(WelcomeStageShellMotion(mode: .enter, isVisible: incomingVisible))
                .environment(\.welcomeStagePhase, .enter(isVisible: incomingVisible))
                .environment(\.welcomeStageParallax, incomingVisible ? parallax : .zero)
                .zIndex(2)
        }
        .onAppear {
            currentStage = stage
            incomingVisible = true
        }
        .onChange(of: stage) { nextStage in
            switchStage(to: nextStage)
        }
        .onDisappear {
            transitionTask?.cancel()
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

    private func switchStage(to nextStage: WelcomeStage) {
        guard nextStage != currentStage else { return }
        transitionTask?.cancel()

        let previousStage = currentStage
        let nextToken = UUID()
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            outgoingStage = previousStage
            currentStage = nextStage
            transitionToken = nextToken
            incomingVisible = false
            outgoingVisible = true
        }

        DispatchQueue.main.async {
            guard transitionToken == nextToken else { return }

            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)) {
                incomingVisible = true
            }
            withAnimation(.easeOut(duration: 0.4)) {
                outgoingVisible = false
            }
        }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, transitionToken == nextToken else { return }
            outgoingStage = nil
        }
    }
}

private struct WelcomeStageLayerID: Hashable {
    let stage: WelcomeStage
    let token: UUID
    let role: WelcomeStageLayerRole
}

private enum WelcomeStageLayerRole: Hashable {
    case incoming
    case outgoing
}

private enum WelcomeStageMotionMode {
    case enter
    case exit
}

private struct WelcomeStageShellMotion: ViewModifier {
    let mode: WelcomeStageMotionMode
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(mode == .enter && isVisible)
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
        case .enter: return 20
        case .exit: return -16
        }
    }

    private var scale: CGFloat {
        switch stagePhase {
        case .enter: return 0.96
        case .exit: return 0.98
        }
    }

    private var animation: Animation {
        switch stagePhase {
        case .enter: return .timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
        case .exit: return .easeOut(duration: 0.4)
        }
    }
}

struct WelcomeStageTextMotion: ViewModifier {
    let delay: Double
    @Environment(\.welcomeStagePhase) private var stagePhase

    func body(content: Content) -> some View {
        content
            .opacity(stagePhase.isVisible ? 1 : 0)
            .offset(y: stagePhase.isVisible ? 0 : verticalOffset)
            .animation(animation, value: stagePhase)
    }

    private var verticalOffset: CGFloat {
        switch stagePhase {
        case .enter: return 20
        case .exit: return -16
        }
    }

    private var animation: Animation {
        switch stagePhase {
        case .enter: return .timingCurve(0.16, 1, 0.3, 1, duration: 0.6).delay(delay)
        case .exit: return .easeOut(duration: 0.4).delay(delay)
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
