import SwiftUI

struct MainWindow: View {
    @StateObject private var model: OnboardingModel

    init(model: OnboardingModel = OnboardingModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            content

            if let toastMessage = model.toastMessage {
                Text(toastMessage)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            await model.bootstrapIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .loadingConfiguration:
            LoadingConfigurationView()
        case .welcome:
            WelcomeStepView(
                onContinue: model.continueFromWelcome,
                onLearnMore: model.openLearnMore
            )
        case .choosePath:
            ChoosePathStepView(
                pathText: Binding(
                    get: { model.repositoryPathText },
                    set: { model.updateRepositoryPath($0) }
                ),
                errorMessage: model.repositoryPathError,
                isValidating: model.isValidatingRepositoryPath,
                canContinue: model.canContinueFromChoosePath,
                onBack: model.showWelcome,
                onChoose: model.chooseRepositoryPath,
                onUseDefault: {
                    Task {
                        await model.useDefaultRepositoryPath()
                    }
                },
                onContinue: {
                    Task {
                        await model.continueFromChoosePath()
                    }
                }
            )
        case .validatePath:
            ValidatePathStepView(
                pathText: model.repositoryPathText,
                validation: model.repositoryPathValidation,
                latestScanSession: model.latestScanSession,
                errorMessage: model.repositoryPathError,
                isValidating: model.isValidatingRepositoryPath,
                isICloudRiskAccepted: model.isICloudRiskAccepted,
                canContinue: model.canContinueFromValidatePath,
                primaryActionTitle: model.validatePathPrimaryActionTitle,
                onBack: model.showChoosePath,
                onChangePath: model.showChoosePath,
                onRetry: {
                    Task {
                        await model.retryRepositoryPathValidation()
                    }
                },
                onICloudRiskAcceptedChanged: model.updateICloudRiskAccepted,
                onContinue: model.continueFromValidatePath
            )
        case .confirmRepositoryInitialization(let draft):
            RepositoryInitializationHandoffView(
                draft: draft,
                onBack: model.showValidatePath,
                onChangePath: model.showChoosePath
            )
        case .repositoryReady(let config):
            RepositoryReadyView(config: config)
        case .configurationError(let failure):
            ConfigurationErrorView(
                failure: failure,
                onRetry: {
                    Task {
                        await model.retryConfigurationLoad()
                    }
                },
                onStartSetup: model.showWelcome
            )
        }
    }
}

private struct RepositoryInitializationHandoffView: View {
    let draft: RepositoryInitializationDraft
    let onBack: () -> Void
    let onChangePath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            repositorySummary
            safetySummary
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("准备接管已有目录")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)
            Text("路径校验已完成，下一步将确认接管范围。")
                .font(.title3)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var repositorySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("资料库路径")
                .font(.headline)
            Text(draft.validation.repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 620, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var safetySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("接管承诺", systemImage: "folder.badge.gearshape")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("AreaMatrix 将只写入 .areamatrix/ 管理目录，保留已有文件、README.md 和目录结构。")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let session = draft.scanSession {
                Text("最近接管扫描：\(session.status.rawValue)，已索引 \(session.inserted) 个项目。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button("Back", action: onBack)
            Button("Change Path", action: onChangePath)
            Spacer()
        }
        .frame(maxWidth: 620)
    }
}

private struct ChoosePathStepView: View {
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

private struct LoadingConfigurationView: View {
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

private struct WelcomeStepView: View {
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
            Text("AreaMatrix")
                .font(.system(size: 40, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)
            Text("把资料放进普通文件夹，让 AreaMatrix 负责索引、分类和记录变化。")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(maxWidth: 620, alignment: .leading)
            Text("你可以随时用 Finder 打开资料库。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Learn more...", action: onLearnMore)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue", action: onContinue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 620)
    }
}

private struct SafetyPromiseList: View {
    private let promises = [
        SafetyPromise(
            title: "普通文件夹",
            message: "你的资料库就是一个文件夹，不是封闭数据库。",
            systemImage: "folder"
        ),
        SafetyPromise(
            title: "本地优先",
            message: "Stage 1 默认不上传任何资料。",
            systemImage: "lock"
        ),
        SafetyPromise(
            title: "可追踪",
            message: "导入、改名、移动和外部修改会写入时间线。",
            systemImage: "clock.arrow.circlepath"
        ),
        SafetyPromise(
            title: "不覆盖已有文档",
            message: "接管目录时不会覆盖已有 README.md 或用户文件。",
            systemImage: "doc.badge.shield"
        ),
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

private struct ConfigurationErrorView: View {
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

private struct RepositoryReadyView: View {
    let config: RepoConfigSnapshot

    var body: some View {
        ContentUnavailableView {
            Label("Repository ready", systemImage: "checkmark.circle")
        } description: {
            Text(config.repoPath)
            Text("Locale: \(config.locale)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
