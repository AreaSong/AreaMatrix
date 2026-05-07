import SwiftUI

struct ImportProgressListRow: Identifiable, Equatable {
    let item: ImportBatchProgressSnapshot.Item

    var id: String { item.id }

    var displayName: String {
        let name = (item.targetPath as NSString).lastPathComponent
        return name.isEmpty ? item.targetPath : name
    }

    var categoryPathDisplay: String {
        let directory = (item.targetPath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? item.targetPath : directory
    }

    var sourcePath: String { item.sourcePath }
    var targetPath: String { item.targetPath }
    var phaseText: String { item.phase.rawValue }
    var errorMessage: String? { item.errorMessage }
}

struct ImportProgressDetailPane: View {
    let row: ImportProgressListRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Import details", systemImage: row.systemImage)
                    .font(.headline)
                metadataRows
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Status", row.phaseText)
            metadataRow("Target", row.targetPath)
            metadataRow("Source", row.sourcePath)
            if let errorMessage = row.errorMessage {
                metadataRow("Error", errorMessage)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }
}

private extension ImportProgressListRow {
    var systemImage: String {
        switch item.phase {
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .pending:
            return "clock"
        case .copying, .moving, .hashing, .classifying, .writingIndex:
            return "arrow.triangle.2.circlepath"
        }
    }
}
