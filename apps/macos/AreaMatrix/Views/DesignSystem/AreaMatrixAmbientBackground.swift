import AreaMatrixUIFoundation
import SwiftUI

private struct AreaMatrixBlobTransform: Equatable {
    let offset: CGSize
    let scale: CGFloat
}

private struct AreaMatrixBlobColorSpec {
    let color: Color
    let opacity: Double
}

struct AreaMatrixAmbientBackground: View {
    let scene: AreaMatrixAmbientScene
    var parallax: AreaMatrixParallax = .zero
    var strength: AreaMatrixMotionTokens.AmbientStrength = .full

    @Environment(\.colorScheme) private var colorScheme
    @State private var blobBreathing = false

    var body: some View {
        ZStack {
            AreaMatrixTheme.Gradients.appBackground(for: colorScheme)
                .ignoresSafeArea()

            AreaMatrixNoiseOverlay()
                .opacity((colorScheme == .dark ? 0.035 : 0.025) * strength.opacityScale)
                .ignoresSafeArea()

            GeometryReader { _ in
                ZStack {
                    blob(
                        size: 500,
                        baseOffset: CGSize(width: -280, height: -170),
                        transform: blob1Transform,
                        color: blobColor(index: 1)
                    )
                    .offset(x: blobBreathing ? 25 : -25, y: blobBreathing ? -20 : 20)
                    .scaleEffect(blobBreathing ? 1.05 : 0.95)
                    .animation(
                        .easeInOut(duration: AreaMatrixMotionTokens.Duration.blobBreathMid)
                            .repeatForever(autoreverses: true),
                        value: blobBreathing
                    )
                    .offset(x: parallax.horizontal * 60, y: parallax.vertical * 40)

                    blob(
                        size: 600,
                        baseOffset: CGSize(width: 230, height: 220),
                        transform: blob2Transform,
                        color: blobColor(index: 2)
                    )
                    .offset(x: blobBreathing ? -28 : 28, y: blobBreathing ? 18 : -18)
                    .scaleEffect(blobBreathing ? 1.08 : 0.92)
                    .animation(
                        .easeInOut(duration: AreaMatrixMotionTokens.Duration.blobBreathExtra)
                            .repeatForever(autoreverses: true)
                            .delay(1),
                        value: blobBreathing
                    )
                    .offset(x: parallax.horizontal * -40, y: parallax.vertical * -50)

                    blob(
                        size: 400,
                        baseOffset: CGSize(width: 28, height: 8),
                        transform: blob3Transform,
                        color: blobColor(index: 3)
                    )
                    .offset(x: blobBreathing ? 18 : -18, y: blobBreathing ? 22 : -22)
                    .scaleEffect(blobBreathing ? 1.04 : 0.96)
                    .animation(
                        .easeInOut(duration: AreaMatrixMotionTokens.Duration.blobBreathLong)
                            .repeatForever(autoreverses: true)
                            .delay(2),
                        value: blobBreathing
                    )
                    .offset(x: parallax.horizontal * 30, y: parallax.vertical * -30)

                    blob(
                        size: 200,
                        baseOffset: CGSize(width: 180, height: -120),
                        transform: blob4Transform,
                        color: blobColor(index: 4)
                    )
                    .offset(x: blobBreathing ? -15 : 15, y: blobBreathing ? 12 : -12)
                    .scaleEffect(blobBreathing ? 1.06 : 0.94)
                    .animation(
                        .easeInOut(duration: AreaMatrixMotionTokens.Duration.blobBreathShort)
                            .repeatForever(autoreverses: true)
                            .delay(3),
                        value: blobBreathing
                    )
                    .offset(x: parallax.horizontal * -20, y: parallax.vertical * 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotationEffect(.degrees(blobBreathing ? 360 : 0))
                .animation(
                    .linear(duration: AreaMatrixMotionTokens.Duration.ambientOrbit)
                        .repeatForever(autoreverses: false),
                    value: blobBreathing
                )
                .onAppear { blobBreathing = true }
                .offset(x: parallax.horizontal * -20, y: parallax.vertical * -20)
                .blur(radius: colorScheme == .dark ? 100 : 75)
                .blendMode(colorScheme == .dark ? .screen : .multiply)
                .opacity((colorScheme == .dark ? 0.9 : 0.6) * strength.opacityScale)
                .animation(.areaMatrixSceneEnterExit, value: scene)
                .animation(.areaMatrixSceneParallax, value: parallax)
            }

            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity((colorScheme == .dark ? 0.25 : 0.08) * strength.opacityScale)
                ],
                center: .center,
                startRadius: 250,
                endRadius: 550
            )
            .allowsHitTesting(false)
        }
        .animation(.areaMatrixSceneEnterExit, value: colorScheme)
    }

    private var blob1Transform: AreaMatrixBlobTransform {
        switch scene {
        case .home: AreaMatrixBlobTransform(offset: CGSize(width: 0, height: 0), scale: 0.5)
        case .classify: AreaMatrixBlobTransform(offset: CGSize(width: 100, height: 75), scale: 1.0)
        case .security: AreaMatrixBlobTransform(offset: CGSize(width: 200, height: 0), scale: 1.0)
        case .tracking: AreaMatrixBlobTransform(offset: CGSize(width: 50, height: 150), scale: 1.0)
        case .help: AreaMatrixBlobTransform(offset: CGSize(width: -100, height: 150), scale: 1.0)
        case .start: AreaMatrixBlobTransform(offset: CGSize(width: -50, height: 100), scale: 1.0)
        }
    }

    private var blob2Transform: AreaMatrixBlobTransform {
        switch scene {
        case .home: AreaMatrixBlobTransform(offset: CGSize(width: 20, height: -20), scale: 0.4)
        case .classify: AreaMatrixBlobTransform(offset: CGSize(width: -60, height: -60), scale: 1.0)
        case .security: AreaMatrixBlobTransform(offset: CGSize(width: -180, height: 60), scale: 1.0)
        case .tracking: AreaMatrixBlobTransform(offset: CGSize(width: -120, height: -180), scale: 1.0)
        case .help: AreaMatrixBlobTransform(offset: CGSize(width: 180, height: -240), scale: 1.0)
        case .start: AreaMatrixBlobTransform(offset: CGSize(width: 120, height: -180), scale: 1.0)
        }
    }

    private var blob3Transform: AreaMatrixBlobTransform {
        switch scene {
        case .home: AreaMatrixBlobTransform(offset: CGSize(width: -20, height: 20), scale: 0.6)
        case .classify: AreaMatrixBlobTransform(offset: CGSize(width: -120, height: 120), scale: 1.0)
        case .security: AreaMatrixBlobTransform(offset: CGSize(width: -40, height: -80), scale: 1.0)
        case .tracking: AreaMatrixBlobTransform(offset: CGSize(width: 120, height: -40), scale: 1.0)
        case .help: AreaMatrixBlobTransform(offset: CGSize(width: 40, height: 80), scale: 1.0)
        case .start: AreaMatrixBlobTransform(offset: CGSize(width: 40, height: 40), scale: 1.0)
        }
    }

    private var blob4Transform: AreaMatrixBlobTransform {
        switch scene {
        case .home: AreaMatrixBlobTransform(offset: CGSize(width: 10, height: -10), scale: 0.4)
        case .classify: AreaMatrixBlobTransform(offset: CGSize(width: -80, height: -100), scale: 0.8)
        case .security: AreaMatrixBlobTransform(offset: CGSize(width: 60, height: 100), scale: 0.8)
        case .tracking: AreaMatrixBlobTransform(offset: CGSize(width: -60, height: -60), scale: 0.8)
        case .help: AreaMatrixBlobTransform(offset: CGSize(width: 100, height: -60), scale: 0.9)
        case .start: AreaMatrixBlobTransform(offset: CGSize(width: -100, height: 60), scale: 0.8)
        }
    }

    private func blobColor(index: Int) -> Color {
        let adjustedIndex = index - 1
        guard blobColorSpecs.indices.contains(adjustedIndex) else { return .clear }
        let spec = blobColorSpecs[adjustedIndex]
        return spec.color.opacity(spec.opacity * opacityMultiplier)
    }

    private var opacityMultiplier: Double {
        (colorScheme == .dark ? 1.0 : 1.5) * strength.opacityScale
    }

    private var blobColorSpecs: [AreaMatrixBlobColorSpec] {
        switch scene {
        case .home:
            [
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.teal, opacity: 0.35),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.gold, opacity: 0.25),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.teal, opacity: 0.15),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.purple, opacity: 0.12)
            ]
        case .classify:
            [
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.teal, opacity: 0.5),
                AreaMatrixBlobColorSpec(color: Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255), opacity: 0.3),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.emerald, opacity: 0.3),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.purple, opacity: 0.2)
            ]
        case .security:
            [
                AreaMatrixBlobColorSpec(color: Color(red: 1, green: 179 / 255, blue: 64 / 255), opacity: 0.45),
                AreaMatrixBlobColorSpec(color: Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255), opacity: 0.35),
                AreaMatrixBlobColorSpec(color: Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255), opacity: 0.25),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.purpleLight, opacity: 0.2)
            ]
        case .tracking:
            [
                AreaMatrixBlobColorSpec(color: Color(red: 1, green: 107 / 255, blue: 107 / 255), opacity: 0.45),
                AreaMatrixBlobColorSpec(color: Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255), opacity: 0.35),
                AreaMatrixBlobColorSpec(color: Color(red: 251 / 255, green: 113 / 255, blue: 133 / 255), opacity: 0.25),
                AreaMatrixBlobColorSpec(color: Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255), opacity: 0.15)
            ]
        case .help:
            [
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.purpleLight, opacity: 0.35),
                AreaMatrixBlobColorSpec(color: Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255), opacity: 0.25),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.purple, opacity: 0.25),
                AreaMatrixBlobColorSpec(color: Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255), opacity: 0.3)
            ]
        case .start:
            [
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.emerald, opacity: 0.4),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.teal, opacity: 0.3),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.emeraldLight, opacity: 0.2),
                AreaMatrixBlobColorSpec(color: AreaMatrixTheme.Colors.purpleLight, opacity: 0.2)
            ]
        }
    }

    private func blob(
        size: CGFloat,
        baseOffset: CGSize,
        transform: AreaMatrixBlobTransform,
        color: Color
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(baseOffset)
            .offset(transform.offset)
            .scaleEffect(transform.scale)
    }
}
