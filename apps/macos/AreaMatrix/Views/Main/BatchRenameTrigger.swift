import SwiftUI

struct BatchRenameTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let renamer: any CoreBatchRenaming
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchRenameReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    @State private var isPresented = false

    var body: some View {
        Button("Rename...") { isPresented = true }
            .help(BatchRenameEntryPolicy.openHelp(disabledReason: disabledReason))
            .accessibilityIdentifier("S2-14-batch-rename-open")
            .sheet(isPresented: $isPresented) {
                BatchRenameSheet(
                    repoPath: repoPath,
                    fileIDs: fileIDs,
                    selectedFiles: selectedFiles,
                    selectedCount: selectedCount,
                    disabledReason: disabledReason,
                    renamer: renamer,
                    undoStore: undoStore,
                    errorMapper: errorMapper,
                    onApplied: onApplied,
                    onUndoStateChange: onUndoStateChange,
                    onClose: { isPresented = false }
                )
            }
    }
}
