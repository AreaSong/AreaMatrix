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
