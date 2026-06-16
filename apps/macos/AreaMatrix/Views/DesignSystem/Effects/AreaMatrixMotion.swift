import SwiftUI

extension Animation {
    static var areaMatrixSpring: Animation {
        .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)
    }

    static var areaMatrixHover: Animation {
        .spring(response: 0.3, dampingFraction: 0.6)
    }

    static var areaMatrixStageFlow: Animation {
        .spring(response: 0.6, dampingFraction: 0.82)
    }

    static var areaMatrixStageEnterExit: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
    }

    static var areaMatrixStageParallax: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)
    }

    static var areaMatrixQuickFade: Animation {
        .easeOut(duration: 0.2)
    }

    static var areaMatrixDeepDive: Animation {
        .timingCurve(0.7, 0, 1, 1, duration: 0.6)
    }
}

extension AnyTransition {
    static var areaMatrixStage: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: AreaMatrixStageTransitionModifier(opacity: 0, yOffset: 20, scale: 0.96),
                identity: AreaMatrixStageTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            ),
            removal: .modifier(
                active: AreaMatrixStageTransitionModifier(opacity: 0, yOffset: -16, scale: 0.98),
                identity: AreaMatrixStageTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            )
        )
    }
}

private struct AreaMatrixStageTransitionModifier: ViewModifier {
    let opacity: Double
    let yOffset: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: yOffset)
    }
}

enum AreaMatrixStagePhase: Equatable {
    case enter(isVisible: Bool)
    case exit(isVisible: Bool)

    var isVisible: Bool {
        switch self {
        case let .enter(isVisible), let .exit(isVisible):
            isVisible
        }
    }
}

private struct AreaMatrixStagePhaseKey: EnvironmentKey {
    static let defaultValue = AreaMatrixStagePhase.enter(isVisible: true)
}

private struct AreaMatrixStageParallaxKey: EnvironmentKey {
    static let defaultValue = AreaMatrixParallax.zero
}

extension EnvironmentValues {
    var areaMatrixStagePhase: AreaMatrixStagePhase {
        get { self[AreaMatrixStagePhaseKey.self] }
        set { self[AreaMatrixStagePhaseKey.self] = newValue }
    }

    var areaMatrixStageParallax: AreaMatrixParallax {
        get { self[AreaMatrixStageParallaxKey.self] }
        set { self[AreaMatrixStageParallaxKey.self] = newValue }
    }
}

struct AreaMatrixStageVisualMotionModifier: ViewModifier {
    @Environment(\.areaMatrixStagePhase) private var stagePhase
    @Environment(\.areaMatrixStageParallax) private var parallax

    func body(content: Content) -> some View {
        content
            .opacity(stagePhase.isVisible ? 1 : 0)
            .offset(y: stagePhase.isVisible ? 0 : verticalOffset)
            .scaleEffect(stagePhase.isVisible ? 1 : scale)
            .blur(radius: stagePhase.isVisible ? 0 : 16)
            .rotationEffect(.degrees(stagePhase.isVisible ? 0 : rotationAngle))
            .rotation3DEffect(
                .degrees(stagePhase.isVisible ? 0 : stage3DRotation),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.85
            )
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
            .animation(.areaMatrixStageEnterExit, value: stagePhase)
            .animation(.areaMatrixStageParallax, value: parallax)
    }

    private var verticalOffset: CGFloat {
        switch stagePhase {
        case .enter: 16
        case .exit: -12
        }
    }

    private var scale: CGFloat {
        switch stagePhase {
        case .enter: 0.85
        case .exit: 1.15
        }
    }

    private var rotationAngle: Double {
        switch stagePhase {
        case .enter: 1.5
        case .exit: -1.5
        }
    }

    private var stage3DRotation: Double {
        switch stagePhase {
        case .enter: -10
        case .exit: 10
        }
    }
}

struct AreaMatrixStageTextMotionModifier: ViewModifier {
    let delay: Double
    @Environment(\.areaMatrixStagePhase) private var stagePhase

    func body(content: Content) -> some View {
        content
            .opacity(stagePhase.isVisible ? 1 : 0)
            .offset(y: stagePhase.isVisible ? 0 : offsetValue)
            .blur(radius: stagePhase.isVisible ? 0 : 4)
            .animation(animation, value: stagePhase)
    }

    private var offsetValue: CGFloat {
        switch stagePhase {
        case .enter: 12
        case .exit: -12
        }
    }

    private var animation: Animation {
        switch stagePhase {
        case .enter:
            .areaMatrixStageEnterExit.delay(delay)
        case .exit:
            .timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
        }
    }
}

struct AreaMatrixFeatureCardFocusModifier: ViewModifier {
    let isHovered: Bool
    let anyCardHovered: Bool

    func body(content: Content) -> some View {
        content
            .opacity(anyCardHovered ? (isHovered ? 1.0 : 0.4) : 1.0)
            .saturation(anyCardHovered ? (isHovered ? 1.0 : 0.4) : 1.0)
            .animation(.areaMatrixHover, value: isHovered)
            .animation(.easeOut(duration: 0.4), value: anyCardHovered)
    }
}

struct AreaMatrixTextShimmerModifier: ViewModifier {
    @State private var shimmerOffset: CGFloat = -1.0
    let primaryColor: Color
    let highlightColor: Color
    let duration: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: primaryColor, location: shimmerOffset),
                        .init(color: highlightColor, location: shimmerOffset + 0.5),
                        .init(color: primaryColor, location: shimmerOffset + 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.0
                }
            }
    }
}

struct AreaMatrixPulseAuraModifier: ViewModifier {
    @State private var isAnimating = false
    let color: Color
    let duration: Double
    let maxScale: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(color.opacity(0.6), lineWidth: 2)
                        .scaleEffect(isAnimating ? maxScale : 0.9)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeOut(duration: duration).repeatForever(autoreverses: false),
                            value: isAnimating
                        )

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                        .scaleEffect(isAnimating ? maxScale : 0.9)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeOut(duration: duration).repeatForever(autoreverses: false).delay(duration * 0.4),
                            value: isAnimating
                        )
                }
            )
            .onAppear {
                isAnimating = true
            }
    }
}

struct AreaMatrixMagneticHoverModifier: ViewModifier {
    @State private var offset: CGSize = .zero
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset.width, y: offset.height)
            .animation(.interpolatingSpring(stiffness: 150, damping: 12), value: offset)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onContinuousHover { phase in
                            updateOffset(for: phase, size: proxy.size)
                        }
                }
            )
    }

    private func updateOffset(for phase: HoverPhase, size: CGSize) {
        switch phase {
        case let .active(location):
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            offset = CGSize(
                width: (location.x - center.x) * intensity,
                height: (location.y - center.y) * intensity
            )
        case .ended:
            offset = .zero
        }
    }
}

extension View {
    func areaMatrixStageVisualMotion() -> some View {
        modifier(AreaMatrixStageVisualMotionModifier())
    }

    func areaMatrixStageTextMotion(delay: Double) -> some View {
        modifier(AreaMatrixStageTextMotionModifier(delay: delay))
    }

    func areaMatrixFeatureCardFocus(isHovered: Bool, anyCardHovered: Bool) -> some View {
        modifier(AreaMatrixFeatureCardFocusModifier(isHovered: isHovered, anyCardHovered: anyCardHovered))
    }

    func areaMatrixTextShimmer(
        primary: Color = .primary,
        highlight: Color,
        duration: Double = 4.0
    ) -> some View {
        modifier(AreaMatrixTextShimmerModifier(primaryColor: primary, highlightColor: highlight, duration: duration))
    }

    func areaMatrixPulseAura(
        color: Color,
        duration: Double = 2.5,
        maxScale: CGFloat = 1.7,
        cornerRadius: CGFloat = 28
    ) -> some View {
        modifier(AreaMatrixPulseAuraModifier(
            color: color,
            duration: duration,
            maxScale: maxScale,
            cornerRadius: cornerRadius
        ))
    }

    func areaMatrixMagneticHover(intensity: CGFloat = 0.2) -> some View {
        modifier(AreaMatrixMagneticHoverModifier(intensity: intensity))
    }
}
