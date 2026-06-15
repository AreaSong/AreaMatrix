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
    @State private var blobBreathing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            NoiseOverlay()
                .opacity(colorScheme == .dark ? 0.035 : 0.025)
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
                    .offset(x: blobBreathing ? 25 : -25, y: blobBreathing ? -20 : 20)
                    .scaleEffect(blobBreathing ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: blobBreathing)
                    .offset(x: parallax.horizontal * 60, y: parallax.vertical * 40)

                    // HTML g2: 600x600, bottom: -200px, right: -100px
                    BlobView(
                        size: 600,
                        baseOffset: CGSize(width: 230, height: 220),
                        transform: blob2Transform,
                        color: blobColor(for: stage, index: 2, isDark: colorScheme == .dark)
                    )
                    .offset(x: blobBreathing ? -28 : 28, y: blobBreathing ? 18 : -18)
                    .scaleEffect(blobBreathing ? 1.08 : 0.92)
                    .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true).delay(1), value: blobBreathing)
                    .offset(x: parallax.horizontal * -40, y: parallax.vertical * -50)

                    // HTML g3: 400x400, top: 20%, left: 30%
                    BlobView(
                        size: 400,
                        baseOffset: CGSize(width: 28, height: 8),
                        transform: blob3Transform,
                        color: blobColor(for: stage, index: 3, isDark: colorScheme == .dark)
                    )
                    .offset(x: blobBreathing ? 18 : -18, y: blobBreathing ? 22 : -22)
                    .scaleEffect(blobBreathing ? 1.04 : 0.96)
                    .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true).delay(2), value: blobBreathing)
                    .offset(x: parallax.horizontal * 30, y: parallax.vertical * -30)

                    // Blob 4: 紫色系互补色，丰富背景色彩层次
                    BlobView(
                        size: 200,
                        baseOffset: CGSize(width: 180, height: -120),
                        transform: blob4Transform,
                        color: blobColor(for: stage, index: 4, isDark: colorScheme == .dark)
                    )
                    .offset(x: blobBreathing ? -15 : 15, y: blobBreathing ? 12 : -12)
                    .scaleEffect(blobBreathing ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(3), value: blobBreathing)
                    .offset(x: parallax.horizontal * -20, y: parallax.vertical * 20)

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotationEffect(.degrees(blobBreathing ? 360 : 0))
                .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: blobBreathing)
                .onAppear { blobBreathing = true }
                .offset(
                    x: parallax.horizontal * -20,
                    y: parallax.vertical * -20
                )
                // 深色保持大模糊营造发光感；浅色收紧让 multiply 色调更集中
                .blur(radius: colorScheme == .dark ? 100 : 75)
                .blendMode(colorScheme == .dark ? .screen : .multiply)
                .opacity(colorScheme == .dark ? 0.9 : 0.6)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8), value: stage)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2), value: parallax)
            }

            // 边缘暗角，引导视觉聚焦中心
            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08)
                ],
                center: .center,
                startRadius: 250,
                endRadius: 550
            )
            .allowsHitTesting(false)
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
            Color(red: 250 / 255, green: 251 / 255, blue: 248 / 255),
            Color(red: 242 / 255, green: 245 / 255, blue: 240 / 255)
        ]
    }

    private var blob1Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: 0, height: 0), scale: 0.5)
        case .feat1:   return BlobTransform(offset: CGSize(width: 100, height: 75), scale: 1.0)
        case .feat2:   return BlobTransform(offset: CGSize(width: 200, height: 0), scale: 1.0)
        case .feat3:   return BlobTransform(offset: CGSize(width: 50, height: 150), scale: 1.0)
        case .feat4:   return BlobTransform(offset: CGSize(width: -100, height: 150), scale: 1.0)
        case .feat5:   return BlobTransform(offset: CGSize(width: -50, height: 100), scale: 1.0)
        }
    }

    private var blob2Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: 20, height: -20), scale: 0.4)
        case .feat1:   return BlobTransform(offset: CGSize(width: -60, height: -60), scale: 1.0)
        case .feat2:   return BlobTransform(offset: CGSize(width: -180, height: 60), scale: 1.0)
        case .feat3:   return BlobTransform(offset: CGSize(width: -120, height: -180), scale: 1.0)
        case .feat4:   return BlobTransform(offset: CGSize(width: 180, height: -240), scale: 1.0)
        case .feat5:   return BlobTransform(offset: CGSize(width: 120, height: -180), scale: 1.0)
        }
    }

    private var blob3Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: -20, height: 20), scale: 0.6)
        case .feat1:   return BlobTransform(offset: CGSize(width: -120, height: 120), scale: 1.0)
        case .feat2:   return BlobTransform(offset: CGSize(width: -40, height: -80), scale: 1.0)
        case .feat3:   return BlobTransform(offset: CGSize(width: 120, height: -40), scale: 1.0)
        case .feat4:   return BlobTransform(offset: CGSize(width: 40, height: 80), scale: 1.0)
        case .feat5:   return BlobTransform(offset: CGSize(width: 40, height: 40), scale: 1.0)
        }
    }

    private var blob4Transform: BlobTransform {
        switch stage {
        case .default: return BlobTransform(offset: CGSize(width: 10, height: -10), scale: 0.4)
        case .feat1:   return BlobTransform(offset: CGSize(width: -80, height: -100), scale: 0.8)
        case .feat2:   return BlobTransform(offset: CGSize(width: 60, height: 100), scale: 0.8)
        case .feat3:   return BlobTransform(offset: CGSize(width: -60, height: -60), scale: 0.8)
        case .feat4:   return BlobTransform(offset: CGSize(width: 100, height: -60), scale: 0.9)
        case .feat5:   return BlobTransform(offset: CGSize(width: -100, height: 60), scale: 0.8)
        }
    }

    private func blobColor(for stage: WelcomeStage, index: Int, isDark: Bool) -> Color {
        let op = isDark ? 1.0 : 1.5
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

        case (.default, 4): return Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.12 * op)
        case (.feat1, 4): return Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.2 * op)
        case (.feat2, 4): return Color(red: 168/255, green: 85/255, blue: 247/255).opacity(0.2 * op)
        case (.feat3, 4): return Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.15 * op)
        case (.feat4, 4): return Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.3 * op)
        case (.feat5, 4): return Color(red: 168/255, green: 85/255, blue: 247/255).opacity(0.2 * op)

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

struct NoiseOverlay: View {
    @State private var noiseImage: Image?

    var body: some View {
        Group {
            if let img = noiseImage {
                img
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
            } else {
                Color.clear
            }
        }
        .onAppear {
            noiseImage = generateNoiseImage()
        }
    }

    private func generateNoiseImage() -> Image? {
        let width = 128
        let height = 128
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var data = [UInt8](repeating: 0, count: width * height)
        for i in 0..<data.count {
            data[i] = UInt8.random(in: 0...255)
        }
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        guard let cgImage = context.makeImage() else { return nil }
        return Image(cgImage, scale: 1, label: Text("Noise"))
    }
}
