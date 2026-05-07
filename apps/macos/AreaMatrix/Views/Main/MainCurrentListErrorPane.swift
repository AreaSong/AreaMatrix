import SwiftUI

struct MainCurrentListErrorPane: View {
    let error: CoreErrorMappingSnapshot
    let state: MainRepositoryContentState
    let fileListModel: MainFileListModel
    let onRetryCurrentList: () -> Void
    let onCollectDiagnostics: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current list cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            actions
            diagnosticsStatus
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        HStack {
            Button("Retry", action: retry)
            Button("Collect Diagnostics...") {
                Task { await collectDiagnostics() }
            }
            .disabled(isCollectingDiagnostics)
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var isCollectingDiagnostics: Bool {
        if case .collecting = fileListModel.diagnosticsState {
            return true
        }
        return false
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch fileListModel.diagnosticsState {
        case .idle:
            EmptyView()
        case .collecting:
            Label("Preparing diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .collected(let snapshot):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
        case .failed(let mapping):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func retry() {
        if state == .list {
            Task { await fileListModel.retryCurrentCategory() }
        } else {
            onRetryCurrentList()
        }
    }

    private func collectDiagnostics() async {
        if state == .list {
            await fileListModel.collectCurrentListDiagnostics()
        } else {
            await onCollectDiagnostics()
        }
    }
}
