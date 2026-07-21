import SwiftUI

struct WelcomeTitlebar: View {
    @Binding var themeOverride: ColorScheme?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Text("AreaMatrix")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                AreaMatrixThemeToggleButton(themeOverride: $themeOverride)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
    }
}

struct WelcomeFeatureCardsGrid: View {
    let activeID: WelcomeScene?
    let onHoverChanged: (WelcomeScene, Bool) -> Void

    var body: some View {
        AreaMatrixFeatureCardGroup(
            cards: featureCards,
            activeID: activeID,
            onHoverChanged: onHoverChanged
        )
    }

    private var featureCards: [AreaMatrixFeatureCardSpec<WelcomeScene>] {
        [
            AreaMatrixFeatureCardSpec(
                id: .feat1,
                icon: "arrow.down.doc",
                title: "拖拽归档，智能分类",
                description: "识别、重命名并自动落位",
                accentColor: AreaMatrixTheme.Colors.tealBright,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard1
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat2,
                icon: "checkmark.shield",
                title: "零侵入，绝对安全",
                description: "不碰原文件，真相在文件系统",
                accentColor: AreaMatrixTheme.Colors.gold,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard2
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat3,
                icon: "rectangle.split.2x1",
                title: "全局概览，改动追溯",
                description: "生成大纲，双向同步改动日志",
                accentColor: AreaMatrixTheme.Colors.coral,
                entranceDelay: AreaMatrixMotionTokens.EntranceDelay.featureCard3
            )
        ]
    }
}
