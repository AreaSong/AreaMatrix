import SwiftUI

enum WelcomeScene: Int, CaseIterable {
    case `default` = 0
    case feat1
    case feat2
    case feat3
    case feat4
    case feat5

    var ambientScene: AreaMatrixAmbientScene {
        switch self {
        case .default: .home
        case .feat1: .classify
        case .feat2: .security
        case .feat3: .tracking
        case .feat4: .help
        case .feat5: .start
        }
    }

    var accentColor: Color {
        ambientScene.accent.color
    }
}

// MARK: - Default Intro

struct WelcomeDefaultSceneView: View {
    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixLaunchBrandVisual()

            AreaMatrixLaunchCopyText(
                title: "将散乱的文件，化作知识枢纽。",
                description: "无需搬运，只需指认一个本地文件夹。AreaMatrix 会为你建立结构清晰、无感同步的私人资料库。"
            )
        }
    }
}

// MARK: - Start CTA

struct WelcomeStartSceneView: View {
    var body: some View {
        VStack(spacing: 32) {
            AreaMatrixFolderLaunchVisual()

            AreaMatrixSceneText(
                title: "立刻开启你的本地知识库",
                description: "放心，我们仅仅是为你指认的文件夹建立一层索引。你可以随时停止使用，没有任何锁定风险。点击即可瞬间接管！"
            )
        }
    }
}
