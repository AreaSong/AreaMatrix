import SwiftUI

struct WelcomeTrackingSceneView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixTimelineDiorama()
                .areaMatrixSceneVisualMotion()
            AreaMatrixSceneText(
                title: "全局概览，时间线级追溯",
                description: "自动生成专属的 Markdown 资料库大纲。您的每一次挪动、修改，哪怕是在系统原生的 Finder 中操作，都会被精准记录并实时回流。",
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.coral : AreaMatrixTheme.Colors.coralDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.goldDeep
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

struct WelcomeHelpSceneView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixSceneParallax) private var parallax

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixWorkflowDiorama()
                .areaMatrixSceneVisualMotion()
                .offset(x: parallax.horizontal * 10, y: parallax.vertical * 10)
            AreaMatrixSceneText(
                title: "工作流与算法揭秘",
                description: "一分钟了解 AreaMatrix 如何通过轻量级的本地索引引擎和 FSEvents 监听，帮助您彻底终结文件整理的焦虑感。",
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.purple : AreaMatrixTheme.Colors.purpleDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.emerald : AreaMatrixTheme.Colors.emeraldDeep
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}
