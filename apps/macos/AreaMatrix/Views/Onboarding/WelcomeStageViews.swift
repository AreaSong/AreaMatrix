import SwiftUI

enum WelcomeStage: Int, CaseIterable {
    case `default` = 0
    case feat1
    case feat2
    case feat3
    case feat4
    case feat5
}

struct WelcomeParallax: Equatable {
    var horizontal: CGFloat
    var vertical: CGFloat

    static let zero = WelcomeParallax(horizontal: 0, vertical: 0)

    var areaMatrixParallax: AreaMatrixParallax {
        AreaMatrixParallax(horizontal: horizontal, vertical: vertical)
    }
}

private struct WelcomeFloatingIconSpec {
    let name: String
    let size: CGFloat
    let offset: CGSize
    let duration: Double
    let delay: Double
}

struct WelcomeScanOverlayView: View {
    let isScanning: Bool
    let terminalLines: [WelcomeTerminalLine]
    let cursorColor: Color
    let scanProgressFraction: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var cursorVisible = true
    @State private var logoPulsing = false

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
                            colors: [AreaMatrixTheme.Colors.tealBright, AreaMatrixTheme.Colors.teal, .clear],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)

                AreaMatrixCrossfadeAssetImage(
                    darkName: "AreaMatrixLogoMarkDark",
                    lightName: "AreaMatrixLogoMarkLight",
                    width: 80,
                    height: 80
                )
                .scaleEffect(logoPulsing ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: logoPulsing)
                .shadow(color: AreaMatrixTheme.Colors.tealBright.opacity(0.5), radius: 12)
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

            // 扫描进度条
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 340, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: [AreaMatrixTheme.Colors.tealBright, AreaMatrixTheme.Colors.gold],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(0, 340 * scanProgressFraction), height: 3)
                    .shadow(color: AreaMatrixTheme.Colors.tealBright.opacity(0.6), radius: 8)
                    .animation(.easeOut(duration: 0.3), value: scanProgressFraction)
            }
        }
        .scaleEffect(isScanning ? 1 : 0.9)
        .opacity(isScanning ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: isScanning)
        .onAppear {
            logoPulsing = true
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

struct WelcomeDropOverlayView: View {
    @State private var isBouncing = false
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(AreaMatrixTheme.Colors.tealBright)
                .offset(y: isBouncing ? -6 : 0)
                .animation(
                    .interpolatingSpring(stiffness: 170, damping: 10).repeatForever(autoreverses: false),
                    value: isBouncing
                )
                .onAppear { isBouncing = true }
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
    @State private var subtitleBreathing = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixCrossfadeAssetImage(
                darkName: "AreaMatrixLogoLockupDark",
                lightName: "AreaMatrixLogoLockupLight",
                width: nil,
                height: 100
            )
            .shadow(color: AreaMatrixTheme.Colors.teal.opacity(0.4), radius: 16, y: 12)
            .offset(y: logoEntered ? 0 : -20)
            .scaleEffect(logoEntered ? 1 : 0.85)
            .animation(.spring(response: 0.75, dampingFraction: 0.55).delay(0.2), value: logoEntered)
            .frame(height: 220)
            .welcomeStageVisualMotion()
            .onAppear {
                logoEntered = true
                subtitleBreathing = true
            }

            VStack(spacing: 8) {
                // 渐变闪光标语——匹配 HTML textShine 动画
                Text("将散乱的文件，化作知识枢纽。")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(0.5)
                    .areaMatrixTextShimmer(highlight: colorScheme == .dark ? AreaMatrixTheme.Colors
                        .tealBright : AreaMatrixTheme.Colors.tealDeep)
                    .welcomeStageTextMotion(delay: 0.05)

                Text("无需搬运，只需指认一个本地文件夹。AreaMatrix 会为你建立结构清晰、无感同步的私人资料库。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(subtitleBreathing ? 0.72 : 1.0)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: subtitleBreathing)
                    .welcomeStageTextMotion(delay: 0.15)
            }
            .frame(maxWidth: 560)
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
                    .areaMatrixPulseAura(color: AreaMatrixTheme.Colors.emeraldLight)

                ForEach(floatingIconSpecs, id: \.name) { spec in
                    floatingDocIcon(spec)
                }

                // 文件夹一体化形状
                AreaMatrixFolderShape(tabWidth: 64, tabHeight: 24, cornerRadius: 16)
                    .fill(AreaMatrixTheme.Colors.emerald.opacity(0.15))
                    .overlay(
                        AreaMatrixFolderShape(tabWidth: 64, tabHeight: 24, cornerRadius: 16)
                            .stroke(AreaMatrixTheme.Colors.tealBright, lineWidth: 3)
                    )
                    .frame(width: 180, height: 148)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .white.opacity(0.9), radius: isAnimating ? 28 : 8)
                            .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: isAnimating)
                            .offset(y: 12)
                    )
                    .offset(y: -12)
                    .shadow(
                        color: AreaMatrixTheme.Colors.emerald.opacity(isAnimating ? 0.6 : 0.3),
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

    private var floatingIconSpecs: [WelcomeFloatingIconSpec] {
        [
            WelcomeFloatingIconSpec(
                name: "doc.text.fill",
                size: 14,
                offset: CGSize(width: -100, height: -25),
                duration: 2.2,
                delay: 0
            ),
            WelcomeFloatingIconSpec(
                name: "photo.fill",
                size: 12,
                offset: CGSize(width: 105, height: 15),
                duration: 2.6,
                delay: 0.5
            ),
            WelcomeFloatingIconSpec(
                name: "tablecells.fill",
                size: 13,
                offset: CGSize(width: -85, height: 45),
                duration: 1.9,
                delay: 1.0
            )
        ]
    }

    private func floatingDocIcon(_ spec: WelcomeFloatingIconSpec) -> some View {
        Image(systemName: spec.name)
            .font(.system(size: spec.size))
            .foregroundColor(AreaMatrixTheme.Colors.tealBright.opacity(0.5))
            .offset(spec.offset)
            .offset(y: isAnimating ? -6 : 6)
            .opacity(isAnimating ? 0.7 : 0.2)
            .animation(
                .easeInOut(duration: spec.duration)
                    .repeatForever(autoreverses: true)
                    .delay(spec.delay),
                value: isAnimating
            )
    }
}

// MARK: - Diorama Stage Text (共享组件)

/// 标准 Stage 文字区：标题 + 描述
struct DioramaStageText: View {
    let title: String
    let description: String
    var gradient: LinearGradient?

    var body: some View {
        VStack(spacing: 12) {
            AreaMatrixDecodedText(text: title, gradient: gradient)
                .font(.system(size: 22, weight: .semibold))
                .tracking(0.5)
                .welcomeStageTextMotion(delay: 0.05)
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .welcomeStageTextMotion(delay: 0.1)
        }
        .frame(maxWidth: 560)
    }
}
