import SwiftUI

struct RepositorySettingsPane: View {
    @StateObject private var model: RepositorySettingsModel

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        _model = StateObject(wrappedValue: RepositorySettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            errorMapper: errorMapper
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.load()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("资料库")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking repository configuration")
            } else {
                Button("Retry status") {
                    Task {
                        await model.load()
                    }
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case .loaded(let summary):
            loadedContent(summary)
        case .failed(let error):
            loadErrorContent(error)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking repository...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorContent(_ error: RepositorySettingsLoadError) -> some View {
        ContentUnavailableView {
            Label("Unable to load repository status", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Retry status") {
                Task {
                    await model.load()
                }
            }
        }
    }

    private func loadedContent(_ summary: RepositorySettingsSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                syncErrorBanner

                RepositorySettingsSection(title: "路径") {
                    RepositorySettingsKeyValueRow(label: "Repository name", value: summary.repositoryName)
                    RepositorySettingsKeyValueRow(label: "Location", value: summary.location)
                }

                RepositorySettingsSection(title: "概览输出") {
                    RepositorySettingsKeyValueRow(label: "Generated overview", value: summary.overviewMode)
                    RepositorySettingsKeyValueRow(label: "Generated path", value: summary.generatedPath)
                    RepositorySettingsKeyValueRow(label: "Root file", value: summary.rootFile)
                    RepositorySettingsKeyValueRow(label: "README.md", value: summary.readmePolicy)
                }

                Text(
                    "Deleting the .areamatrix folder removes AreaMatrix metadata, not your original files. " +
                        "Do this only if you know what you are doing."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
    }

    @ViewBuilder
    private var syncErrorBanner: some View {
        if let error = model.syncError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }
}

private struct RepositorySettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RepositorySettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
    }
}
