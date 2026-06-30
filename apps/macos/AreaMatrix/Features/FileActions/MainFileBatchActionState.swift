import Foundation

enum MainFileBatchActionRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
    case commandPalette
}

enum MainFileBatchActionEligibility {
    static func disabledReason(
        selectedFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> String? {
        if selectedFiles.isEmpty { return "No files selected" }
        return selectedFiles.compactMap {
            MainFileWriteActionEligibility.disabledReason(
                fileID: $0.id,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )?.message
        }.first
    }

    static func disabledReason(
        summary: MultiSelectionDetailSummary,
        blocksWhileUpdating: Bool,
        writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    ) -> String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if blocksWhileUpdating, summary.isUpdating {
            return MainFileWriteActionDisabledReason.listLoading.message
        }
        return summary.files.compactMap { writeActionDisabledReason($0.id)?.message }.first
    }
}

enum MainFileBatchEntryPolicy {
    static func openHelp(
        disabledReason: String?,
        defaultHelp: String,
        blockedHelpSuffix: String
    ) -> String {
        disabledReason.map { "\($0). \(blockedHelpSuffix)" } ?? defaultHelp
    }

    static func disabledReason(
        selectedFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> String? {
        MainFileBatchActionEligibility.disabledReason(
            selectedFiles: selectedFiles,
            isReadOnly: isReadOnly,
            isLoading: isLoading,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }

    static func disabledReason(
        summary: MultiSelectionDetailSummary,
        blocksWhileUpdating: Bool,
        writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    ) -> String? {
        MainFileBatchActionEligibility.disabledReason(
            summary: summary,
            blocksWhileUpdating: blocksWhileUpdating,
            writeActionDisabledReason: writeActionDisabledReason
        )
    }
}

struct MainFileBatchActionRoutePayload: Equatable {
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?

    init(
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot] = [],
        selectedCount: Int,
        disabledReason: String?
    ) {
        self.fileIDs = fileIDs
        self.selectedFiles = selectedFiles
        self.selectedCount = selectedCount
        self.disabledReason = disabledReason
    }

    init(context: MainFileBatchActionRouteContext) {
        self.init(
            fileIDs: context.fileIDs,
            selectedFiles: context.selectedFiles,
            selectedCount: context.selectedCount,
            disabledReason: context.disabledReason
        )
    }

    var identityParts: [String] {
        [
            fileIDs.map(String.init).joined(separator: ","),
            "\(selectedCount)",
            disabledReason ?? ""
        ]
    }
}

struct MainFileBatchActionRouteContext: Equatable {
    let selectedFiles: [FileEntrySnapshot]
    let isReadOnly: Bool
    let isLoading: Bool
    let writeLockedFileIDs: Set<Int64>

    init(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) {
        selectedFiles = visibleFiles.filter { selectedFileIDs.contains($0.id) }
        self.isReadOnly = isReadOnly
        self.isLoading = isLoading
        self.writeLockedFileIDs = writeLockedFileIDs
    }

    var fileIDs: [Int64] {
        selectedFiles.map(\.id)
    }

    var selectedCount: Int {
        selectedFiles.count
    }

    var disabledReason: String? {
        MainFileBatchActionEligibility.disabledReason(
            selectedFiles: selectedFiles,
            isReadOnly: isReadOnly,
            isLoading: isLoading,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }
}

struct MainFileBatchActionTriggerContext: Equatable {
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?

    init(
        summary: MultiSelectionDetailSummary,
        fileIDs: [Int64],
        blocksWhileUpdating: Bool,
        writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    ) {
        self.fileIDs = fileIDs
        selectedFiles = summary.files
        selectedCount = summary.selectedCount
        disabledReason = MainFileBatchEntryPolicy.disabledReason(
            summary: summary,
            blocksWhileUpdating: blocksWhileUpdating,
            writeActionDisabledReason: writeActionDisabledReason
        )
    }

    static func defaultAction(
        selection: MainFileSelectionState,
        summary: MultiSelectionDetailSummary,
        writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    ) -> MainFileBatchActionTriggerContext {
        MainFileBatchActionTriggerContext(
            summary: summary,
            fileIDs: selection.multipleFileIDs.sorted(),
            blocksWhileUpdating: false,
            writeActionDisabledReason: writeActionDisabledReason
        )
    }

    static func updatingBlockedAction(
        selection: MainFileSelectionState,
        summary: MultiSelectionDetailSummary,
        writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    ) -> MainFileBatchActionTriggerContext {
        MainFileBatchActionTriggerContext(
            summary: summary,
            fileIDs: selection.multipleFileIDs.sorted(),
            blocksWhileUpdating: true,
            writeActionDisabledReason: writeActionDisabledReason
        )
    }

    static func renamePreview(
        summary: MultiSelectionDetailSummary,
        writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    ) -> MainFileBatchActionTriggerContext {
        MainFileBatchActionTriggerContext(
            summary: summary,
            fileIDs: BatchRenameEntryPolicy.fileIDsForPreview(summary: summary),
            blocksWhileUpdating: true,
            writeActionDisabledReason: writeActionDisabledReason
        )
    }
}

enum BatchFileActionRouteBuilder {
    static func batchAddTagsRoute(
        source: MainFileBatchActionRouteSource,
        context: MainFileBatchActionRouteContext
    ) -> BatchAddTagsRoute {
        BatchAddTagsRoute(source: source, context: context)
    }

    static func batchChangeCategoryRoute(
        source: MainFileBatchActionRouteSource,
        context: MainFileBatchActionRouteContext
    ) -> BatchChangeCategoryRoute {
        BatchChangeCategoryRoute(source: source, context: context)
    }

    static func batchDeleteRoute(
        source: MainFileBatchActionRouteSource,
        context: MainFileBatchActionRouteContext
    ) -> BatchDeleteRoute {
        BatchDeleteRoute(source: source, context: context)
    }

    static func batchRenameRoute(
        source: MainFileBatchActionRouteSource,
        context: MainFileBatchActionRouteContext
    ) -> BatchRenameRoute {
        BatchRenameRoute(source: source, context: context)
    }

    static func commandPaletteBatchAddTagsRoute(context: MainFileBatchActionRouteContext) -> BatchAddTagsRoute {
        batchAddTagsRoute(source: .commandPalette, context: context)
    }

    static func commandPaletteBatchChangeCategoryRoute(
        context: MainFileBatchActionRouteContext
    ) -> BatchChangeCategoryRoute {
        batchChangeCategoryRoute(source: .commandPalette, context: context)
    }

    static func commandPaletteBatchDeleteRoute(context: MainFileBatchActionRouteContext) -> BatchDeleteRoute {
        batchDeleteRoute(source: .commandPalette, context: context)
    }

    static func commandPaletteBatchRenameRoute(context: MainFileBatchActionRouteContext) -> BatchRenameRoute {
        batchRenameRoute(source: .commandPalette, context: context)
    }
}
