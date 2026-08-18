import SwiftUI

public extension Animation {
    static var areaMatrixSpring: Animation {
        .spring(
            response: AreaMatrixMotionTokens.Spring.response,
            dampingFraction: AreaMatrixMotionTokens.Spring.damping,
            blendDuration: 0
        )
    }

    static var areaMatrixHover: Animation {
        .spring(
            response: AreaMatrixMotionTokens.Spring.hoverResponse,
            dampingFraction: AreaMatrixMotionTokens.Spring.hoverDamping
        )
    }

    static var areaMatrixSceneFlow: Animation {
        .spring(
            response: AreaMatrixMotionTokens.Spring.response,
            dampingFraction: AreaMatrixMotionTokens.Spring.sceneFlowDamping
        )
    }

    static var areaMatrixSceneEnterExit: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: AreaMatrixMotionTokens.Duration.sceneEnterExit)
    }

    static var areaMatrixSceneParallax: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: AreaMatrixMotionTokens.Duration.sceneParallax)
    }

    static var areaMatrixOverlayFade: Animation {
        .easeInOut(duration: AreaMatrixMotionTokens.Duration.overlayFade)
    }

    static var areaMatrixProgressStep: Animation {
        .easeOut(duration: AreaMatrixMotionTokens.Duration.progressStep)
    }

    static var areaMatrixFlashIn: Animation {
        .easeIn(duration: AreaMatrixMotionTokens.Duration.flash)
    }

    static var areaMatrixQuickFade: Animation {
        .easeOut(duration: AreaMatrixMotionTokens.Duration.quickFade)
    }

    static var areaMatrixDeepDive: Animation {
        .timingCurve(0.7, 0, 1, 1, duration: AreaMatrixMotionTokens.Duration.deepDive)
    }

    static var areaMatrixEntrance: Animation {
        .easeOut(duration: AreaMatrixMotionTokens.Duration.entrance)
    }

    static var areaMatrixThemeToggle: Animation {
        .easeInOut(duration: AreaMatrixMotionTokens.Duration.themeToggle)
    }

    static var areaMatrixGlowBreath: Animation {
        .easeInOut(duration: AreaMatrixMotionTokens.Duration.glowBreath).repeatForever(autoreverses: true)
    }

    static var areaMatrixPulseAura: Animation {
        .easeOut(duration: AreaMatrixMotionTokens.Duration.pulseAura).repeatForever(autoreverses: false)
    }
}

private struct AreaMatrixFeatureCardFocusModifier: ViewModifier {
    let isHovered: Bool
    let anyCardHovered: Bool

    func body(content: Content) -> some View {
        content
            .opacity(anyCardHovered ? (isHovered ? 1.0 : 0.4) : 1.0)
            .saturation(anyCardHovered ? (isHovered ? 1.0 : 0.4) : 1.0)
            .animation(.areaMatrixHover, value: isHovered)
            .animation(
                .easeOut(duration: AreaMatrixMotionTokens.Duration.hoverSettle),
                value: anyCardHovered
            )
    }
}

private struct AreaMatrixTextShimmerModifier: ViewModifier {
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

private struct AreaMatrixPulseAuraModifier: ViewModifier {
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
                            .easeOut(duration: duration)
                                .repeatForever(autoreverses: false)
                                .delay(duration * 0.4),
                            value: isAnimating
                        )
                }
            )
            .onAppear {
                isAnimating = true
            }
    }
}

private struct AreaMatrixMagneticHoverModifier: ViewModifier {
    @State private var offset: CGSize = .zero
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset.width, y: offset.height)
            .animation(
                .interpolatingSpring(
                    stiffness: AreaMatrixMotionTokens.Spring.magneticStiffness,
                    damping: AreaMatrixMotionTokens.Spring.magneticDamping
                ),
                value: offset
            )
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

private struct AreaMatrixDelayedEntranceModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : AreaMatrixMotionTokens.Intensity.entranceOffsetY)
            .animation(.areaMatrixEntrance.delay(delay), value: isVisible)
    }
}

private struct AreaMatrixScanningContentModifier: ViewModifier {
    let isScanning: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isScanning ? 12 : 0)
            .scaleEffect(isScanning ? 0.92 : 1)
            .opacity(isScanning ? 0 : 1)
            .animation(.areaMatrixSpring, value: isScanning)
    }
}

private struct AreaMatrixDeepDiveModifier: ViewModifier {
    let isActive: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? scale : 1.0)
            .animation(.areaMatrixDeepDive, value: isActive)
    }
}

public extension View {
    func areaMatrixFeatureCardFocus(isHovered: Bool, anyCardHovered: Bool) -> some View {
        modifier(AreaMatrixFeatureCardFocusModifier(isHovered: isHovered, anyCardHovered: anyCardHovered))
    }

    func areaMatrixTextShimmer(
        primary: Color = .primary,
        highlight: Color,
        duration: Double = AreaMatrixMotionTokens.Duration.textShimmer
    ) -> some View {
        modifier(AreaMatrixTextShimmerModifier(primaryColor: primary, highlightColor: highlight, duration: duration))
    }

    func areaMatrixPulseAura(
        color: Color,
        duration: Double = AreaMatrixMotionTokens.Duration.pulseAura,
        maxScale: CGFloat = AreaMatrixMotionTokens.Intensity.pulseAuraMaxScale,
        cornerRadius: CGFloat = 28
    ) -> some View {
        modifier(
            AreaMatrixPulseAuraModifier(
                color: color,
                duration: duration,
                maxScale: maxScale,
                cornerRadius: cornerRadius
            )
        )
    }

    func areaMatrixMagneticHover(intensity: CGFloat = AreaMatrixMotionTokens.Intensity.magneticDefault) -> some View {
        modifier(AreaMatrixMagneticHoverModifier(intensity: intensity))
    }

    func areaMatrixDelayedEntrance(
        isVisible: Bool,
        delay: Double = AreaMatrixMotionTokens.EntranceDelay.body
    ) -> some View {
        modifier(AreaMatrixDelayedEntranceModifier(isVisible: isVisible, delay: delay))
    }

    func areaMatrixPageContentEntrance(
        delay: Double = AreaMatrixMotionTokens.EntranceDelay.body
    ) -> some View {
        modifier(AreaMatrixPageContentEntranceModifier(delay: delay))
    }

    func areaMatrixScanningContent(isScanning: Bool) -> some View {
        modifier(AreaMatrixScanningContentModifier(isScanning: isScanning))
    }

    func areaMatrixDeepDive(isActive: Bool, scale: CGFloat) -> some View {
        modifier(AreaMatrixDeepDiveModifier(isActive: isActive, scale: scale))
    }
}

private struct AreaMatrixPageContentEntranceModifier: ViewModifier {
    @State private var entered = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .areaMatrixDelayedEntrance(isVisible: entered, delay: delay)
            .onAppear { entered = true }
    }
}
