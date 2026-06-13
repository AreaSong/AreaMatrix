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

// MARK: - Stage Default

struct StageDefaultView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        VStack(spacing: 32) {
            Image(colorScheme == .dark ? "AreaMatrixLogoLockupDark" : "AreaMatrixLogoLockupLight")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .shadow(color: WelcomePalette.teal.opacity(0.4), radius: 16, y: 12)

            VStack(spacing: 8) {
                // 渐变闪光标语——匹配 HTML textShine 动画
                Text("将散乱的文件，化作知识枢纽。")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .primary, location: max(0, shimmerOffset)),
                                .init(color: WelcomePalette.tealBright, location: min(1, shimmerOffset + 0.5)),
                                .init(color: .primary, location: min(1, shimmerOffset + 1.0)),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("无需搬运，只需指认一个本地文件夹。AreaMatrix 会为你建立结构清晰、无感同步的私人资料库。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: 560)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.0
            }
        }
    }
}

// MARK: - Stage 5 Start

struct StageStartView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                // 扩散光环 1
                RoundedRectangle(cornerRadius: 28)
                    .stroke(WelcomePalette.emeraldLight.opacity(0.6), lineWidth: 2)
                    .frame(width: 200, height: 144)
                    .scaleEffect(isAnimating ? 1.7 : 0.9)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        .easeOut(duration: 2.5).repeatForever(autoreverses: false),
                        value: isAnimating
                    )

                // 扩散光环 2（延迟）
                RoundedRectangle(cornerRadius: 28)
                    .stroke(WelcomePalette.emeraldLight.opacity(0.3), lineWidth: 1)
                    .frame(width: 220, height: 164)
                    .scaleEffect(isAnimating ? 1.7 : 0.9)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        .easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(1),
                        value: isAnimating
                    )

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

            VStack(spacing: 12) {
                Text("立刻开启您的本地知识库")
                    .font(.system(size: 22, weight: .semibold))
                Text("放心，我们仅仅是为您指认的文件夹建立一层索引。您可以随时停止使用，没有任何锁定风险。点击即可瞬间接管！")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
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

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar
            HStack(spacing: 4) {
                Circle().fill(Color(red: 1, green: 0.373, blue: 0.337)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1, green: 0.741, blue: 0.18)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.153, green: 0.788, blue: 0.247)).frame(width: 8, height: 8)
                Spacer()
                Text(title)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 28)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.black.opacity(0.15))

            content()
        }
        .frame(width: width, height: height)
        .background(useDarkBackground ? .ultraThinMaterial : .ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 560)
    }
}
