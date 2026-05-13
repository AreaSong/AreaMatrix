import SwiftUI

struct DetailExternalCreateSyncStatusView: View {
    let state: MainDetailExternalCreateSyncState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .syncing(event):
            Label(
                "Syncing external \(event.kind.displayName) file: \(event.relativePath)",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .synced(event, fileID, result):
            syncedStatus(event: event, fileID: fileID, result: result)
        case let .failed(event, mapping):
            failedStatus(event: event, mapping: mapping)
        }
    }

    private func syncedStatus(
        event: MainExternalCreatedFileEvent,
        fileID: Int64?,
        result: SyncResultSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("External \(event.kind.displayName) file synced", systemImage: "checkmark.circle")
            Text(summary(event: event, fileID: fileID, result: result))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func failedStatus(
        event: MainExternalCreatedFileEvent,
        mapping: CoreErrorMappingSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("External \(event.kind.displayName) sync failed", systemImage: "exclamationmark.triangle")
            Text(event.relativePath)
                .foregroundStyle(.secondary)
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(8)
        .background(Color.yellow.opacity(0.12))
    }

    private func summary(
        event: MainExternalCreatedFileEvent,
        fileID: Int64?,
        result: SyncResultSnapshot
    ) -> String {
        let fileText = fileID.map { "file #\($0)" } ?? "file not selected"
        return """
        \(event.relativePath) · \(fileText) · created \(result.detectedCreates) · \
        renamed \(result.detectedRenames) · deleted \(result.detectedDeletes)
        """
    }
}
