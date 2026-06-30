import Foundation

struct BatchRenameRoute: Identifiable, Equatable {
    let source: MainFileBatchActionRouteSource
    private let payload: MainFileBatchActionRoutePayload

    var fileIDs: [Int64] {
        payload.fileIDs
    }

    var selectedFiles: [FileEntrySnapshot] {
        payload.selectedFiles
    }

    var selectedCount: Int {
        payload.selectedCount
    }

    var disabledReason: String? {
        payload.disabledReason
    }

    var id: String {
        ([source.rawValue] + payload.identityParts).joined(separator: ":")
    }

    init(
        source: MainFileBatchActionRouteSource,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot],
        selectedCount: Int,
        disabledReason: String?
    ) {
        self.source = source
        payload = MainFileBatchActionRoutePayload(
            fileIDs: fileIDs,
            selectedFiles: selectedFiles,
            selectedCount: selectedCount,
            disabledReason: disabledReason
        )
    }
}

extension BatchRenameRoute {
    init(source: MainFileBatchActionRouteSource, context: MainFileBatchActionRouteContext) {
        self.init(source: source, payload: MainFileBatchActionRoutePayload(context: context))
    }

    private init(source: MainFileBatchActionRouteSource, payload: MainFileBatchActionRoutePayload) {
        self.source = source
        self.payload = payload
    }
}

enum BatchRenameEntryPolicy {
    static func fileIDsForPreview(summary: MultiSelectionDetailSummary) -> [Int64] {
        summary.listOrderedFileIDs
    }

    static func openHelp(disabledReason: String?) -> String {
        MainFileBatchEntryPolicy.openHelp(
            disabledReason: disabledReason,
            defaultHelp: "Preview batch rename for the selected files",
            blockedHelpSuffix: "Preview new file names before renaming."
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
            return await .failed(errorMapper.mapError(error), previous: nil)
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
            return await BatchRenameApplyResult(
                report: nil,
                failure: errorMapper.mapError(error)
            )
        }
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
