import SwiftUI

enum WelcomeStage: Int, CaseIterable {
    case `default` = 0
    case feat1
    case feat2
    case feat3
    case feat4
    case feat5
}

struct WelcomeAmbientBackground: View {
    let stage: WelcomeStage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Blobs
            GeometryReader { proxy in
                ZStack {
                    BlobView(
                        color: blobColor(for: stage, index: 1, isDark: colorScheme == .dark),
                        offset: blobOffset(for: stage, index: 1, in: proxy.size)
                    )

                    BlobView(
                        color: blobColor(for: stage, index: 2, isDark: colorScheme == .dark),
                        offset: blobOffset(for: stage, index: 2, in: proxy.size)
                    )

                    BlobView(
                        color: blobColor(for: stage, index: 3, isDark: colorScheme == .dark),
                        offset: blobOffset(for: stage, index: 3, in: proxy.size)
                    )
                }
                .blur(radius: 80)
                // In dark mode, plusLighter or screen creates a nice glowing blend effect
                .blendMode(colorScheme == .dark ? .screen : .normal)
                .opacity(0.8)
            }
        }
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8), value: stage)
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8), value: colorScheme)
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 13 / 255, green: 40 / 255, blue: 35 / 255),
                Color(red: 7 / 255, green: 21 / 255, blue: 19 / 255),
            ]
        }

        return [
            Color.white,
            Color(red: 242 / 255, green: 247 / 255, blue: 245 / 255),
        ]
    }

    private func blobColor(for stage: WelcomeStage, index: Int, isDark: Bool) -> Color {
        let opacityMultiplier = isDark ? 1.0 : 1.2
        let colors = blobColors(for: stage, opacityMultiplier: opacityMultiplier)
        return colors[index - 1]
    }

    private func blobColors(for stage: WelcomeStage, opacityMultiplier: Double) -> [Color] {
        switch stage {
        case .default:
            [
                WelcomePalette.teal.opacity(0.35 * opacityMultiplier),
                WelcomePalette.gold.opacity(0.25 * opacityMultiplier),
                WelcomePalette.teal.opacity(0.15 * opacityMultiplier),
            ]
        case .feat1:
            [
                WelcomePalette.teal.opacity(0.5 * opacityMultiplier),
                Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255).opacity(0.3),
                WelcomePalette.emerald.opacity(0.3 * opacityMultiplier),
            ]
        case .feat2:
            [
                Color(red: 1, green: 179 / 255, blue: 64 / 255).opacity(0.45),
                Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255).opacity(0.35),
                Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255).opacity(0.25 * opacityMultiplier),
            ]
        case .feat3:
            [
                Color(red: 1, green: 107 / 255, blue: 107 / 255).opacity(0.45),
                Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255).opacity(0.35),
                Color(red: 251 / 255, green: 113 / 255, blue: 133 / 255).opacity(0.25 * opacityMultiplier),
            ]
        case .feat4:
            [
                WelcomePalette.purpleLight.opacity(0.35 * opacityMultiplier),
                Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255).opacity(0.25),
                WelcomePalette.purple.opacity(0.25 * opacityMultiplier),
            ]
        case .feat5:
            [
                WelcomePalette.emerald.opacity(0.4 * opacityMultiplier),
                WelcomePalette.teal.opacity(0.3 * opacityMultiplier),
                WelcomePalette.emeraldLight.opacity(0.2 * opacityMultiplier),
            ]
        }
    }

    private func blobOffset(for stage: WelcomeStage, index: Int, in _: CGSize) -> CGSize {
        let offsets = blobOffsets(for: stage)
        return offsets[index - 1]
    }

    private func blobOffsets(for stage: WelcomeStage) -> [CGSize] {
        switch stage {
        case .default:
            [
                CGSize(width: 150, height: -50),
                CGSize(width: -200, height: 100),
                CGSize(width: -50, height: -20),
            ]
        case .feat1:
            [
                CGSize(width: 100, height: -80),
                CGSize(width: -50, height: -50),
                CGSize(width: -150, height: 100),
            ]
        case .feat2:
            [
                CGSize(width: 200, height: 0),
                CGSize(width: -150, height: 50),
                CGSize(width: -50, height: -100),
            ]
        case .feat3:
            [
                CGSize(width: 50, height: 100),
                CGSize(width: -100, height: -150),
                CGSize(width: 150, height: -50),
            ]
        case .feat4:
            [
                CGSize(width: -100, height: 100),
                CGSize(width: 150, height: -150),
                CGSize(width: 50, height: 80),
            ]
        case .feat5:
            [
                CGSize(width: -50, height: 80),
                CGSize(width: 100, height: -100),
                CGSize(width: 50, height: 40),
            ]
        }
    }
}

private struct BlobView: View {
    var color: Color
    var offset: CGSize

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 400, height: 400)
            .offset(offset)
    }
}
