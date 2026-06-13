import SwiftUI

struct SettingsRepositoryReturnView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Repository settings", systemImage: "gearshape")
        } description: {
            Text("Repository change was cancelled before opening a new repository.")
        }
    }
}

struct ChoosePathStepView: View {
    @Binding var pathText: String

    let errorMessage: String?
    let isValidating: Bool
    let canContinue: Bool
    let onBack: () -> Void
    let onChoose: () -> Void
    let onUseDefault: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            recommendedLocation
            pathSelection
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择资料库位置")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)
            Text("资料库是一个普通文件夹，你可以随时在 Finder 中访问。")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var recommendedLocation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("推荐位置")
                .font(.headline)
            Text("~/AreaMatrix/")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var pathSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("路径")
                .font(.headline)
            HStack(spacing: 10) {
                TextField("Repository path", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Repository path")
                    .disabled(isValidating)
                Button("Choose...", action: onChoose)
                    .disabled(isValidating)
            }
            .frame(maxWidth: 620)
            pathHelp
        }
    }

    @ViewBuilder
    private var pathHelp: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        } else {
            Text("接管已有目录不会移动、改名、删除或覆盖原有内容。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back", action: onBack)
                .disabled(isValidating)
            Spacer()
            if isValidating {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Use default", action: onUseDefault)
                .disabled(isValidating)
            Button("Continue", action: onContinue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
        }
        .frame(maxWidth: 620)
    }
}

struct LoadingConfigurationView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading repository settings...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            SafetyPromiseList()
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("AreaMatrixLogoLockup")
                .resizable()
                .scaledToFit()
                .frame(width: 320, height: 104, alignment: .leading)
                .accessibilityLabel("AreaMatrix")
            Text("本地索引你的大文件夹。")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("连接 OneDrive、iCloud 或本地目录，首次扫描后先读本地索引，变化再后台同步。")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(maxWidth: 620, alignment: .leading)
            Text("文件留在原处；默认不下载内容、不移动、不删除、不覆盖。")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Button("了解索引如何工作", action: onLearnMore)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            Button("连接文件夹", action: onContinue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 620)
    }
}

private struct SafetyPromiseList: View {
    private let promises = [
        SafetyPromise(
            title: "扫一次",
            message: "保存目录树和文件信息，后续打开不用等云盘重新加载。",
            systemImage: "folder.badge.clock"
        ),
        SafetyPromise(
            title: "云盘友好",
            message: "支持 OneDrive、iCloud 和本地目录，提示占位与冲突风险。",
            systemImage: "cloud"
        ),
        SafetyPromise(
            title: "上下分栏",
            message: "上方看层级，下方看列表、预览、详情和记录。",
            systemImage: "rectangle.split.2x1"
        ),
        SafetyPromise(
            title: "原件不动",
            message: "只建立索引和元数据，不改动已有文件。",
            systemImage: "checkmark.shield"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(promises) { promise in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: promise.systemImage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(promise.title)
                            .font(.headline)
                        Text(promise.message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }
}

private struct SafetyPromise: Identifiable {
    let title: String
    let message: String
    let systemImage: String

    var id: String {
        title
    }
}

struct ConfigurationErrorView: View {
    let failure: ConfigLoadFailure
    let onRetry: () -> Void
    let onStartSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(failure.title, systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
            Text(failure.message)
                .foregroundStyle(.secondary)
            Text(failure.recoveryAction)
                .foregroundStyle(.secondary)
            HStack {
                Button("Start setup", action: onStartSetup)
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(48)
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .center)
    }
}
