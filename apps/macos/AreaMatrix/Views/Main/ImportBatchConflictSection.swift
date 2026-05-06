import SwiftUI

struct ImportBatchConflictSection: View {
    let duplicateCount: Int
    let batchImportModel: ImportBatchCopyImportModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded || duplicateCount > 0 {
                conflictsTable
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review conflicts")
                    .font(.headline)
                Text("\(batchImportModel.duplicateCount) duplicates · 0 name conflict · 0 blocked")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isExpanded ? "Hide" : "Review conflicts") {
                isExpanded.toggle()
            }
        }
    }

    private var conflictsTable: some View {
        Table(batchImportModel.rows.filter(\.isDuplicateConflictRow)) {
            TableColumn("File") { row in
                Text(row.originalName)
            }
            TableColumn("Conflict") { _ in
                Text("Duplicate content")
            }
            TableColumn("Existing item") { row in
                Text(duplicateExistingPath(for: row) ?? "-")
            }
            TableColumn("Incoming resolution") { row in
                Text(row.suggestedName)
            }
            TableColumn("Strategy") { row in
                duplicateStrategyPicker(for: row)
            }
            TableColumn("Status") { row in
                Text(row.status.detail ?? row.status.tag)
            }
            TableColumn("Action") { _ in
                Text("Show existing file")
            }
        }
        .frame(minHeight: 120)
    }

    private func duplicateStrategyPicker(for row: ImportBatchCopyImportRow) -> some View {
        Picker("Strategy", selection: Binding(
            get: { row.duplicateResolution ?? .skip },
            set: { batchImportModel.updateDuplicateStrategy(for: row.id, strategy: $0) }
        )) {
            ForEach(ImportBatchDuplicateResolutionStrategy.allCases, id: \.self) { strategy in
                Text(strategy.title).tag(strategy)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 150)
        .disabled(batchImportModel.status.isImporting)
    }

    private func duplicateExistingPath(for row: ImportBatchCopyImportRow) -> String? {
        switch row.status {
        case .duplicate(let existingPath, _), .skippedDuplicate(let existingPath):
            return existingPath
        case .loading, .ready, .importing, .imported, .error:
            return nil
        }
    }
}
