import SwiftUI

enum WelcomeStage: Int, CaseIterable {
    case `default` = 0
    case feat1
    case feat2
    case feat3
    case feat4
    case feat5
}

private struct BlobTransform: Equatable {
    let offset: CGSize
    let scale: CGFloat
}

struct WelcomeAmbientBackground: View {
    let stage: WelcomeStage
    let parallax: WelcomeParallax
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    // HTML g1: 500x500, top: -100px, left: -100px
                    BlobView(
                        size: 500,
                        baseOffset: CGSize(width: -280, height: -170),
                        transform: blob1Transform,
                        color: blobColor(for: stage, index: 1, isDark: colorScheme == .dark)
                    )

                    // HTML g2: 600x600, bottom: -200px, right: -100px
                    BlobView(
                        size: 600,
                        baseOffset: CGSize(width: 230, height: 220),
                        transform: blob2Transform,
                        color: blobColor(for: stage, index: 2, isDark: colorScheme == .dark)
                    )

                    // HTML g3: 400x400, top: 20%, left: 30%
                    BlobView(
                        size: 400,
                        baseOffset: CGSize(width: 28, height: 8),
                        transform: blob3Transform,
                        color: blobColor(for: stage, index: 3, isDark: colorScheme == .dark)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(
                    x: parallax.horizontal * -20,
                    y: parallax.vertical * -20
                )
                // HTML: .g-blob filter: blur(80px)
                .blur(radius: 80)
                .blendMode(colorScheme == .dark ? .screen : .normal)
                .opacity(colorScheme == .dark ? 0.9 : 0.6)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8), value: stage)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2), value: parallax)
            }
        }
        // HTML: transition: all 0.8s cubic-bezier(0.16, 1, 0.3, 1)
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8), value: colorScheme)
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 13 / 255, green: 40 / 255, blue: 35 / 255),
                Color(red: 7 / 255, green: 21 / 255, blue: 19 / 255)
            ]
        }
        return [
            Color.white,
            Color(red: 242 / 255, green: 247 / 255, blue: 245 / 255)
        ]
    }

    private var blob1Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: 340, height: 147), scale: 0.8)
        case .feat1:   return BlobTransform(offset: CGSize(width: 100, height: 75), scale: 1.0)
        case .feat2:   return BlobTransform(offset: CGSize(width: 200, height: 0), scale: 1.0)
        case .feat3:   return BlobTransform(offset: CGSize(width: 50, height: 150), scale: 1.0)
        case .feat4:   return BlobTransform(offset: CGSize(width: -100, height: 150), scale: 1.0)
        case .feat5:   return BlobTransform(offset: CGSize(width: -50, height: 100), scale: 1.0)
        }
    }

    private var blob2Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: -290, height: -363), scale: 0.6)
        case .feat1:   return BlobTransform(offset: CGSize(width: -60, height: -60), scale: 1.0)
        case .feat2:   return BlobTransform(offset: CGSize(width: -180, height: 60), scale: 1.0)
        case .feat3:   return BlobTransform(offset: CGSize(width: -120, height: -180), scale: 1.0)
        case .feat4:   return BlobTransform(offset: CGSize(width: 180, height: -240), scale: 1.0)
        case .feat5:   return BlobTransform(offset: CGSize(width: 120, height: -180), scale: 1.0)
        }
    }

    private var blob3Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: -102, height: -55), scale: 0.7)
        case .feat1:   return BlobTransform(offset: CGSize(width: -120, height: 120), scale: 1.0)
        case .feat2:   return BlobTransform(offset: CGSize(width: -40, height: -80), scale: 1.0)
        case .feat3:   return BlobTransform(offset: CGSize(width: 120, height: -40), scale: 1.0)
        case .feat4:   return BlobTransform(offset: CGSize(width: 40, height: 80), scale: 1.0)
        case .feat5:   return BlobTransform(offset: CGSize(width: 40, height: 40), scale: 1.0)
        }
    }

    private func blobColor(for stage: WelcomeStage, index: Int, isDark: Bool) -> Color {
        let op = isDark ? 1.0 : 0.6
        switch (stage, index) {
        case (.default, 1): return Color(red: 21/255, green: 180/255, blue: 159/255).opacity(0.35 * op)
        case (.default, 2): return Color(red: 241/255, green: 184/255, blue: 78/255).opacity(0.25 * op)
        case (.default, 3): return Color(red: 21/255, green: 180/255, blue: 159/255).opacity(0.15 * op)
            
        case (.feat1, 1): return Color(red: 21/255, green: 180/255, blue: 159/255).opacity(0.5 * op)
        case (.feat1, 2): return Color(red: 14/255, green: 165/255, blue: 233/255).opacity(0.3 * op)
        case (.feat1, 3): return Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.3 * op)
            
        case (.feat2, 1): return Color(red: 255/255, green: 179/255, blue: 64/255).opacity(0.45 * op)
        case (.feat2, 2): return Color(red: 251/255, green: 146/255, blue: 60/255).opacity(0.35 * op)
        case (.feat2, 3): return Color(red: 250/255, green: 204/255, blue: 21/255).opacity(0.25 * op)
            
        case (.feat3, 1): return Color(red: 255/255, green: 107/255, blue: 107/255).opacity(0.45 * op)
        case (.feat3, 2): return Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.35 * op)
        case (.feat3, 3): return Color(red: 251/255, green: 113/255, blue: 133/255).opacity(0.25 * op)
            
        case (.feat4, 1): return Color(red: 168/255, green: 85/255, blue: 247/255).opacity(0.35 * op)
        case (.feat4, 2): return Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.25 * op)
        case (.feat4, 3): return Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.25 * op)
            
        case (.feat5, 1): return Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.4 * op)
        case (.feat5, 2): return Color(red: 21/255, green: 180/255, blue: 159/255).opacity(0.3 * op)
        case (.feat5, 3): return Color(red: 52/255, green: 211/255, blue: 153/255).opacity(0.2 * op)
            
        default: return .clear
        }
    }
}

private struct BlobView: View {
    let size: CGFloat
    let baseOffset: CGSize
    let transform: BlobTransform
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(baseOffset)
            .offset(transform.offset)
            .scaleEffect(transform.scale)
    }
}
