import SwiftUI

struct StageClassifyView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixClassificationDiorama()
                .areaMatrixStageVisualMotion()
            AreaMatrixStageText(
                title: "智能引擎，自动归档",
                description: "把文件拖入视窗，底层的智能规则与 AI 将自动识别内容、建议命名，并为其在庞大复杂的目录树中寻找到最佳的物理归属。",
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors.emeraldDeep
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

struct StageSecurityView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixProtectionDiorama()
                .areaMatrixStageVisualMotion()
            AreaMatrixStageText(
                title: "零侵入，绝对的安全防线",
                description: "我们仅仅在底层建立一层可视化的超级索引。程序承诺永远不会在后台私自改动、移动或覆盖您宝贵的源文件与已有目录结构。",
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.goldDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.coral : AreaMatrixTheme.Colors.coralDeep
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
