import SwiftUI

extension Animation {
    static var areaMatrixSpring: Animation {
        .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)
    }

    static var areaMatrixHover: Animation {
        .spring(response: 0.3, dampingFraction: 0.6)
    }

    static var areaMatrixSceneFlow: Animation {
        .spring(response: 0.6, dampingFraction: 0.82)
    }

    static var areaMatrixSceneEnterExit: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
    }

    static var areaMatrixSceneParallax: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)
    }

    static var areaMatrixOverlayFade: Animation {
        .easeInOut(duration: 0.8)
    }

    static var areaMatrixProgressStep: Animation {
        .easeOut(duration: 0.8)
    }

    static var areaMatrixFlashIn: Animation {
        .easeIn(duration: 0.15)
    }

    static var areaMatrixQuickFade: Animation {
        .easeOut(duration: 0.2)
    }

    static var areaMatrixDeepDive: Animation {
        .timingCurve(0.7, 0, 1, 1, duration: 0.6)
    }
}

extension AnyTransition {
    static var areaMatrixScene: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: AreaMatrixSceneTransitionModifier(opacity: 0, yOffset: 20, scale: 0.96),
                identity: AreaMatrixSceneTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            ),
            removal: .modifier(
                active: AreaMatrixSceneTransitionModifier(opacity: 0, yOffset: -16, scale: 0.98),
                identity: AreaMatrixSceneTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            )
        )
    }
}

private struct AreaMatrixSceneTransitionModifier: ViewModifier {
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

enum AreaMatrixSceneVisibility: Equatable {
    case enter(isVisible: Bool)
    case exit(isVisible: Bool)

    var isVisible: Bool {
        switch self {
        case let .enter(isVisible), let .exit(isVisible):
            isVisible
        }
    }
}

private struct AreaMatrixSceneVisibilityKey: EnvironmentKey {
    static let defaultValue = AreaMatrixSceneVisibility.enter(isVisible: true)
}

private struct AreaMatrixSceneParallaxKey: EnvironmentKey {
    static let defaultValue = AreaMatrixParallax.zero
}

extension EnvironmentValues {
    var areaMatrixSceneVisibility: AreaMatrixSceneVisibility {
        get { self[AreaMatrixSceneVisibilityKey.self] }
        set { self[AreaMatrixSceneVisibilityKey.self] = newValue }
    }

    var areaMatrixSceneParallax: AreaMatrixParallax {
        get { self[AreaMatrixSceneParallaxKey.self] }
        set { self[AreaMatrixSceneParallaxKey.self] = newValue }
    }
}

extension AreaMatrixParallax {
    init(pointerLocation location: CGPoint, in size: CGSize) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        self.init(
            horizontal: ((location.x / width) - 0.5) * 2,
            vertical: ((location.y / height) - 0.5) * 2
        )
    }

    static func fromHoverPhase(_ phase: HoverPhase, in size: CGSize) -> AreaMatrixParallax {
        switch phase {
        case let .active(location):
            AreaMatrixParallax(pointerLocation: location, in: size)
        case .ended:
            .zero
        }
    }
}

struct AreaMatrixSceneVisualMotionModifier: ViewModifier {
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility
    @Environment(\.areaMatrixSceneParallax) private var parallax

    func body(content: Content) -> some View {
        content
            .opacity(sceneVisibility.isVisible ? 1 : 0)
            .offset(y: sceneVisibility.isVisible ? 0 : verticalOffset)
            .scaleEffect(sceneVisibility.isVisible ? 1 : scale)
            .blur(radius: sceneVisibility.isVisible ? 0 : 16)
            .rotationEffect(.degrees(sceneVisibility.isVisible ? 0 : rotationAngle))
            .rotation3DEffect(
                .degrees(sceneVisibility.isVisible ? 0 : scene3DRotation),
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
            .animation(.areaMatrixSceneEnterExit, value: sceneVisibility)
            .animation(.areaMatrixSceneParallax, value: parallax)
    }

    private var verticalOffset: CGFloat {
        switch sceneVisibility {
        case .enter: 16
        case .exit: -12
        }
    }

    private var scale: CGFloat {
        switch sceneVisibility {
        case .enter: 0.85
        case .exit: 1.15
        }
    }

    private var rotationAngle: Double {
        switch sceneVisibility {
        case .enter: 1.5
        case .exit: -1.5
        }
    }

    private var scene3DRotation: Double {
        switch sceneVisibility {
        case .enter: -10
        case .exit: 10
        }
    }
}

struct AreaMatrixSceneTextMotionModifier: ViewModifier {
    let delay: Double
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility

    func body(content: Content) -> some View {
        content
            .opacity(sceneVisibility.isVisible ? 1 : 0)
            .offset(y: sceneVisibility.isVisible ? 0 : offsetValue)
            .blur(radius: sceneVisibility.isVisible ? 0 : 4)
            .animation(animation, value: sceneVisibility)
    }

    private var offsetValue: CGFloat {
        switch sceneVisibility {
        case .enter: 12
        case .exit: -12
        }
    }

    private var animation: Animation {
        switch sceneVisibility {
        case .enter:
            .areaMatrixSceneEnterExit.delay(delay)
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

struct AreaMatrixDelayedEntranceModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(delay), value: isVisible)
    }
}

struct AreaMatrixScanningContentModifier: ViewModifier {
    let isScanning: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isScanning ? 12 : 0)
            .scaleEffect(isScanning ? 0.92 : 1)
            .opacity(isScanning ? 0 : 1)
            .animation(.areaMatrixSpring, value: isScanning)
    }
}

struct AreaMatrixDeepDiveModifier: ViewModifier {
    let isActive: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? scale : 1.0)
            .animation(.areaMatrixDeepDive, value: isActive)
    }
}

extension View {
    func areaMatrixSceneVisualMotion() -> some View {
        modifier(AreaMatrixSceneVisualMotionModifier())
    }

    func areaMatrixSceneTextMotion(delay: Double) -> some View {
        modifier(AreaMatrixSceneTextMotionModifier(delay: delay))
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

    func areaMatrixDelayedEntrance(isVisible: Bool, delay: Double) -> some View {
        modifier(AreaMatrixDelayedEntranceModifier(isVisible: isVisible, delay: delay))
    }

    func areaMatrixScanningContent(isScanning: Bool) -> some View {
        modifier(AreaMatrixScanningContentModifier(isScanning: isScanning))
    }

    func areaMatrixDeepDive(isActive: Bool, scale: CGFloat) -> some View {
        modifier(AreaMatrixDeepDiveModifier(isActive: isActive, scale: scale))
    }
}
