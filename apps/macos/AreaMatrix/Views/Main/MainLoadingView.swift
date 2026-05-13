import SwiftUI

struct MainLoadingView: View {
    let state: MainLoadingState
    let isRetryingStartupRecovery: Bool
    let onCancelOpening: () -> Void
    let onRetryStartupRecovery: () -> Void
    let onRetryTree: () -> Void
    let onRetryOpening: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView(state.accessibilityStatusText)
                .controlSize(.large)
                .accessibilityLabel(state.accessibilityStatusText)
            Text("正在打开资料库...")
                .font(.title2.weight(.semibold))
            pathBox
            recoverySection
            treeLoadingSection
            openingErrorSection
            scanSection
            safetyText
            Button("Cancel opening", action: onCancelOpening)
                .accessibilityHint("Cancel opening returns to folder validation and does not modify user files.")
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var pathBox: some View {
        Text(state.repoPath)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let startupRecovery = state.startupRecovery {
            StartupRecoveryErrorRecoveryView(
                state: startupRecovery,
                isRetrying: isRetryingStartupRecovery,
                onRetry: onRetryStartupRecovery
            )
            .accessibilityLabel(state.recoveryStatusText ?? "Startup recovery")
        }
    }

    @ViewBuilder
    private var openingErrorSection: some View {
        if let mapping = state.repositoryOpeningErrorMapping {
            VStack(alignment: .leading, spacing: 8) {
                Label("Repository is temporarily unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
                Button("Retry", action: onRetryOpening)
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.repositoryOpeningErrorText ?? mapping.userMessage)
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        if let status = state.scanStatusText {
            VStack(alignment: .leading, spacing: 6) {
                Text(status)
                    .font(.headline)
                if let progress = state.scanProgressText {
                    Text(progress)
                }
                if let currentPath = state.scanCurrentPathText {
                    Text(currentPath)
                        .lineLimit(2)
                }
                if let warning = state.scanWarningText {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scanning changes. \(status)")
        }
    }

    @ViewBuilder
    private var treeLoadingSection: some View {
        if let treeLoading = state.treeLoading {
            VStack(alignment: .leading, spacing: 8) {
                Label(state.treeStatusText ?? "正在加载资料库目录...", systemImage: treeIcon(for: treeLoading))
                    .font(.headline)
                    .foregroundStyle(treeColor(for: treeLoading))

                switch treeLoading {
                case .loading:
                    TreeSkeletonView()
                case .loaded:
                    TreeLoadedRowsView(rows: state.treeRows)
                case let .failed(mapping):
                    Text(mapping.suggestedAction)
                        .foregroundStyle(.secondary)
                    Button("Retry Tree", action: onRetryTree)
                }
            }
            .padding(14)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.treeStatusText ?? "Loading repository tree")
        }
    }

    private var safetyText: some View {
        Text(
            [
                "Cancel opening only stops the UI opening flow.",
                "AreaMatrix does not move, rename, delete, or overwrite user files."
            ].joined(separator: " ")
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func treeIcon(for state: MainLoadingTreeState) -> String {
        switch state {
        case .loading:
            "sidebar.left"
        case .loaded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private func treeColor(for state: MainLoadingTreeState) -> Color {
        switch state {
        case .failed:
            .orange
        default:
            .primary
        }
    }
}

private struct TreeSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(index == 0 ? 0.22 : 0.14))
                    .frame(width: CGFloat(180 - index * 22), height: 10)
            }
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }
}

private struct TreeLoadedRowsView: View {
    let rows: [RepositorySidebarRowSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.prefix(5)) { row in
                HStack(spacing: 8) {
                    Text(row.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(row.totalFileCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(row.depth * 14))
            }
        }
        .font(.callout)
    }
}
