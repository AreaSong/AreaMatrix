import Foundation

enum BatchRenameRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
    case commandPalette
}

struct BatchRenameRoute: Identifiable, Equatable {
    let source: BatchRenameRouteSource
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?

    var id: String {
        [
            source.rawValue,
            fileIDs.map(String.init).joined(separator: ","),
            "\(selectedCount)",
            disabledReason ?? ""
        ].joined(separator: ":")
    }
}

extension BatchRenameRoute {
    init(source: BatchRenameRouteSource, context: MainFileBatchActionRouteContext) {
        self.source = source
        fileIDs = context.fileIDs
        selectedFiles = context.selectedFiles
        selectedCount = context.selectedCount
        disabledReason = context.disabledReason
    }
}

enum BatchRenameEntryPolicy {
    static func fileIDsForPreview(summary: MultiSelectionDetailSummary) -> [Int64] {
        summary.listOrderedFileIDs
    }

    static func openHelp(disabledReason: String?) -> String {
        disabledReason.map { "\($0). Preview new file names before renaming." } ??
            "Preview batch rename for the selected files"
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
}

struct BatchRenameRuleDraft: Equatable {
    var mode: BatchRenameModeSnapshot = .prefix
    var prefix = ""
    var dateSource: BatchRenameDateSourceSnapshot = .imported
    var dateFormat = "yyyy-MM-dd"
    var separator = "_"
    var startNumber = 1
    var padding = 2
    var find = ""
    var replacement = ""
    var caseSensitive = false

    var snapshot: BatchRenameRuleSnapshot {
        BatchRenameRuleSnapshot(
            mode: mode,
            prefix: trimmed(prefix),
            dateSource: mode == .datePrefix ? dateSource : nil,
            dateFormat: mode == .datePrefix ? trimmed(dateFormat) : nil,
            separator: mode == .datePrefix || mode == .keepBaseSequence ? separator : nil,
            startNumber: mode == .keepBaseSequence ? Int64(startNumber) : nil,
            padding: mode == .keepBaseSequence ? Int64(padding) : nil,
            find: mode == .replaceText ? trimmed(find) : nil,
            replacement: mode == .replaceText ? replacement : nil,
            caseSensitive: mode == .replaceText && caseSensitive
        )
    }

    var validationMessage: String? {
        switch mode {
        case .datePrefix where dateFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            "Date format is required."
        case .keepBaseSequence where startNumber < 0:
            "Start number must be 0 or greater."
        case .keepBaseSequence where padding < 1:
            "Padding must be 1 or greater."
        case .replaceText where find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            "Find is required."
        case .prefix, .datePrefix, .keepBaseSequence, .replaceText:
            nil
        }
    }

    var previewKey: String {
        [
            mode.rawValue,
            prefix,
            dateSource.rawValue,
            dateFormat,
            separator,
            "\(startNumber)",
            "\(padding)",
            find,
            replacement,
            "\(caseSensitive)"
        ].joined(separator: "|")
    }

    private func trimmed(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct BatchRenameApplyResult: Equatable {
    var report: BatchRenameReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

enum BatchRenamePreviewState: Equatable {
    case idle
    case loading(previous: BatchRenamePreviewReportSnapshot?)
    case loaded(BatchRenamePreviewReportSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: BatchRenamePreviewReportSnapshot?)

    var applyReport: BatchRenamePreviewReportSnapshot? {
        guard case let .loaded(report) = self else { return nil }
        return report
    }

    var displayReport: BatchRenamePreviewReportSnapshot? {
        switch self {
        case let .loaded(report), let .loading(report?), let .failed(_, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping, _) = self else { return nil }
        return mapping
    }
}

enum BatchRenameAction {
    static func preview(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenamePreviewState {
        do {
            let report = try await renamer.previewBatchRename(repoPath: repoPath, fileIDs: fileIDs, rule: rule)
            return .loaded(report)
        } catch {
            return await .failed(mapError(error, errorMapper: errorMapper), previous: nil)
        }
    }

    static func apply(
        repoPath: String,
        fileIDs: [Int64],
        preview: BatchRenamePreviewReportSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenameApplyResult {
        do {
            let report = try await renamer.batchRename(
                repoPath: repoPath,
                fileIDs: fileIDs,
                rule: preview.rule,
                previewToken: preview.previewToken
            )
            return BatchRenameApplyResult(report: report, failure: nil)
        } catch {
            return await BatchRenameApplyResult(report: nil, failure: mapError(error, errorMapper: errorMapper))
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

enum BatchRenameValidation {
    static func canApply(
        fileIDs: [Int64],
        preview: BatchRenamePreviewReportSnapshot?,
        rule: BatchRenameRuleSnapshot,
        disabledReason: String?,
        isApplying: Bool
    ) -> Bool {
        guard !isApplying,
              disabledReason == nil,
              !fileIDs.isEmpty,
              let preview,
              preview.canApply,
              preview.rule == rule,
              preview.requestedFileCount == Int64(fileIDs.count) else { return false }
        return preview.items.map(\.fileID) == fileIDs
    }
}

extension BatchRenameReportSnapshot {
    var successfulRenameCount: Int64 {
        renamedCount + displayNameUpdatedCount
    }

    var shouldRefreshConsumerAfterApply: Bool {
        successfulRenameCount > 0 || !updatedFiles.isEmpty || undoToken != nil
    }

    var shouldCloseSheetAfterApply: Bool {
        failedCount == 0
    }
}
