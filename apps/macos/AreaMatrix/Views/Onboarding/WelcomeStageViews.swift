import SwiftUI

// MARK: - Shared Palette

enum WelcomePalette {
    static let teal = Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255)
    static let tealBright = Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255)
    static let gold = Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255)
    static let coral = Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255)
    static let purple = Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255)
    static let purpleLight = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
    static let emerald = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    static let emeraldLight = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
}

struct WelcomeParallax: Equatable {
    var horizontal: CGFloat
    var vertical: CGFloat

    static let zero = WelcomeParallax(horizontal: 0, vertical: 0)
}

struct WelcomeCrossfadeAssetImage: View {
    let darkName: String
    let lightName: String
    let width: CGFloat?
    let height: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            logoImage(lightName)
                .opacity(colorScheme == .dark ? 0 : 1)
            logoImage(darkName)
                .opacity(colorScheme == .dark ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.6), value: colorScheme)
    }

    private func logoImage(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }
}

struct WelcomeScanOverlayView: View {
    let isScanning: Bool
    let terminalLines: [WelcomeTerminalLine]
    let cursorColor: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var cursorVisible = true

    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), lineWidth: 2)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0.0, to: 0.32)
                    .stroke(
                        AngularGradient(
                            colors: [WelcomePalette.tealBright, WelcomePalette.teal, .clear],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)

                WelcomeCrossfadeAssetImage(
                    darkName: "AreaMatrixLogoMarkDark",
                    lightName: "AreaMatrixLogoMarkLight",
                    width: 80,
                    height: 80
                )
                .shadow(color: WelcomePalette.tealBright.opacity(0.5), radius: 12)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(terminalLines) { line in
                    Text(line.text)
                        .foregroundColor(line.color)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Text("█")
                    .foregroundColor(cursorColor)
                    .opacity(cursorVisible ? 1 : 0.18)
            }
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(width: 340, alignment: .leading)
            .shadow(color: cursorColor.opacity(0.4), radius: 8)
        }
        .scaleEffect(isScanning ? 1 : 0.9)
        .opacity(isScanning ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: isScanning)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

struct WelcomeDropOverlayView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(WelcomePalette.tealBright)
                .symbolEffect(.bounce, options: .repeating)
            Text("释放以交由 AreaMatrix 接管")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.18))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// MARK: - Stage Default

struct StageDefaultView: View {
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var logoEntered = false

    var body: some View {
        VStack(spacing: 32) {
            WelcomeCrossfadeAssetImage(
                darkName: "AreaMatrixLogoLockupDark",
                lightName: "AreaMatrixLogoLockupLight",
                width: nil,
                height: 100
            )
            .shadow(color: WelcomePalette.teal.opacity(0.4), radius: 16, y: 12)
            .offset(y: logoEntered ? 0 : -20)
            .animation(.spring(response: 0.9, dampingFraction: 0.65).delay(0.2), value: logoEntered)
            .frame(height: 220)
            .welcomeStageVisualMotion()
            .onAppear { logoEntered = true }

            VStack(spacing: 8) {
                // 渐变闪光标语——匹配 HTML textShine 动画
                Text("将散乱的文件，化作知识枢纽。")
                    .font(.system(size: 20, weight: .semibold))
                    .textShimmer(highlight: WelcomePalette.tealBright)

                Text("无需搬运，只需指认一个本地文件夹。AreaMatrix 会为你建立结构清晰、无感同步的私人资料库。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560)
            .welcomeStageTextMotion(delay: 0.05)
        }
    }
}

// MARK: - Stage 5 Start

struct StageStartView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.clear)
                    .frame(width: 200, height: 144)
                    .pulseAura(color: WelcomePalette.emeraldLight)

                // 浮动文件图标
                floatingDocIcon("doc.text.fill", size: 14, x: -100, y: -25, duration: 2.2, delay: 0)
                floatingDocIcon("photo.fill", size: 12, x: 105, y: 15, duration: 2.6, delay: 0.5)
                floatingDocIcon("tablecells.fill", size: 13, x: -85, y: 45, duration: 1.9, delay: 1.0)

                // 大文件夹
                ZStack {
                    // 文件夹 tab
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(WelcomePalette.tealBright, lineWidth: 3)
                        .frame(width: 64, height: 24)
                        .background(WelcomePalette.emerald.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                        .offset(x: -61, y: -74)

                    // 文件夹主体
                    RoundedRectangle(cornerRadius: 20)
                        .fill(WelcomePalette.emerald.opacity(0.15))
                        .frame(width: 180, height: 124)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(WelcomePalette.tealBright, lineWidth: 3)
                        )
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .white.opacity(0.9), radius: 20)
                        )
                }
                .shadow(
                    color: WelcomePalette.emerald.opacity(isAnimating ? 0.6 : 0.3),
                    radius: isAnimating ? 40 : 20
                )
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(
                    .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            }
            .frame(height: 220)
            .welcomeStageVisualMotion()

            VStack(spacing: 12) {
                Text("立刻开启你的本地知识库")
                    .font(.system(size: 22, weight: .semibold))
                    .welcomeStageTextMotion(delay: 0.05)
                Text("放心，我们仅仅是为你指认的文件夹建立一层索引。你可以随时停止使用，没有任何锁定风险。点击即可瞬间接管！")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .welcomeStageTextMotion(delay: 0.1)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
    }

    private func floatingDocIcon(
        _ name: String, size: CGFloat,
        x: CGFloat, y: CGFloat,
        duration: Double, delay: Double
    ) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundColor(WelcomePalette.tealBright.opacity(0.5))
            .offset(x: x, y: y)
            .offset(y: isAnimating ? -6 : 6)
            .opacity(isAnimating ? 0.7 : 0.2)
            .animation(
                .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
    }
}

// MARK: - Mock Mini Window (共享组件)

/// 匹配 HTML mini-mac-window 样式的 Diorama 窗口壳
struct MockMiniWindow<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var useDarkBackground: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar
            HStack(spacing: 8) {
                WelcomeTrafficLights()
                    .scaleEffect(0.67)
                    .frame(width: 34, height: 12)
                Spacer()
                Text(title)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 28)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.12))

            content()
        }
        .frame(width: width, height: height)
        .background(useDarkBackground ? .ultraThinMaterial : .ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
    }
}

// MARK: - Diorama Stage Text (共享组件)

/// 标准 Stage 文字区：标题 + 描述
struct DioramaStageText: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .welcomeStageTextMotion(delay: 0.05)
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .welcomeStageTextMotion(delay: 0.1)
        }
        .frame(maxWidth: 560)
    }
}
