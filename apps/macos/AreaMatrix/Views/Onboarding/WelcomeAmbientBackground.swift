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
    @State private var animateGradients = false

    var body: some View {
        ZStack {
            // Background
            Color(colorScheme == .dark ? NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1) : NSColor(calibratedRed: 0.91, green: 0.925, blue: 0.92, alpha: 1))
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

    private func blobColor(for stage: WelcomeStage, index: Int, isDark: Bool) -> Color {
        let opacityMultiplier = isDark ? 1.0 : 1.2
        switch stage {
        case .default:
            if index == 1 { return Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.35 * opacityMultiplier) }
            if index == 2 { return Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255).opacity(0.25 * opacityMultiplier) }
            return Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.15 * opacityMultiplier)
        case .feat1:
            if index == 1 { return Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.5 * opacityMultiplier) }
            if index == 2 { return Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255).opacity(0.3 * opacityMultiplier) }
            return Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.3 * opacityMultiplier)
        case .feat2:
            if index == 1 { return Color(red: 255 / 255, green: 179 / 255, blue: 64 / 255).opacity(0.45 * opacityMultiplier) }
            if index == 2 { return Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255).opacity(0.35 * opacityMultiplier) }
            return Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255).opacity(0.25 * opacityMultiplier)
        case .feat3:
            if index == 1 { return Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255).opacity(0.45 * opacityMultiplier) }
            if index == 2 { return Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255).opacity(0.35 * opacityMultiplier) }
            return Color(red: 251 / 255, green: 113 / 255, blue: 133 / 255).opacity(0.25 * opacityMultiplier)
        case .feat4:
            if index == 1 { return Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255).opacity(0.35 * opacityMultiplier) }
            if index == 2 { return Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255).opacity(0.25 * opacityMultiplier) }
            return Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255).opacity(0.25 * opacityMultiplier)
        case .feat5:
            if index == 1 { return Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.4 * opacityMultiplier) }
            if index == 2 { return Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.3 * opacityMultiplier) }
            return Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255).opacity(0.2 * opacityMultiplier)
        }
    }

    private func blobOffset(for stage: WelcomeStage, index: Int, in size: CGSize) -> CGSize {
        // Base translation derived from CSS logic
        let cx = size.width / 2
        let cy = size.height / 2

        switch stage {
        case .default:
            if index == 1 { return CGSize(width: cx + 150, height: cy - 50) }
            if index == 2 { return CGSize(width: cx - 200, height: cy + 100) }
            return CGSize(width: cx - 50, height: cy - 20)
        case .feat1:
            if index == 1 { return CGSize(width: cx + 100, height: cy - 80) }
            if index == 2 { return CGSize(width: cx - 50, height: cy - 50) }
            return CGSize(width: cx - 150, height: cy + 100)
        case .feat2:
            if index == 1 { return CGSize(width: cx + 200, height: cy) }
            if index == 2 { return CGSize(width: cx - 150, height: cy + 50) }
            return CGSize(width: cx - 50, height: cy - 100)
        case .feat3:
            if index == 1 { return CGSize(width: cx + 50, height: cy + 100) }
            if index == 2 { return CGSize(width: cx - 100, height: cy - 150) }
            return CGSize(width: cx + 150, height: cy - 50)
        case .feat4:
            if index == 1 { return CGSize(width: cx - 100, height: cy + 100) }
            if index == 2 { return CGSize(width: cx + 150, height: cy - 150) }
            return CGSize(width: cx + 50, height: cy + 80)
        case .feat5:
            if index == 1 { return CGSize(width: cx - 50, height: cy + 80) }
            if index == 2 { return CGSize(width: cx + 100, height: cy - 100) }
            return CGSize(width: cx + 50, height: cy + 40)
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
