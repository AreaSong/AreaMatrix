import Foundation

extension MainFileListModel {
    @discardableResult
    func submitRename(fileID: Int64, newName: String) async -> Bool {
        guard pendingActionDestination == .rename(fileID: fileID),
              !renameState.isRenaming,
              writeActionDisabledReason(fileID: fileID) == nil else { return false }

        let returnTargetCategory = renameState.changeCategoryReturnTarget(for: fileID)
        renameState = renameState.renamingState(fileID: fileID, targetCategory: returnTargetCategory)
        do {
            let renamedFile = try await fileRenamer.renameFile(
                repoPath: repoPath,
                fileID: fileID,
                newName: newName
            )
            applyRenamedFile(renamedFile)
            renameState = .idle
            if let returnTargetCategory {
                changeCategoryState = .idle
                pendingActionDestination = .changeCategory(
                    fileID: renamedFile.id,
                    initialTargetCategory: returnTargetCategory
                )
            } else {
                pendingActionDestination = nil
            }
            statusBanner = .renamedPreservedSelection(fileID: renamedFile.id)
            if selection.singleFileID == renamedFile.id {
                await loadChangeLog(fileID: renamedFile.id)
                if case let .loaded(loadedFileID, _) = detailLogState, loadedFileID == renamedFile.id {
                    detailTabRequest = .automatic(.log)
                }
            }
            return true
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .rename(fileID: fileID) else { return false }
            renameState = renameState.failedState(
                fileID: fileID,
                targetCategory: returnTargetCategory,
                mapping: mapping
            )
            return false
        }
    }

    private func applyRenamedFile(_ renamedFile: FileEntrySnapshot) {
        files = files.map { file in
            file.id == renamedFile.id ? renamedFile : file
        }
        selection = .single(renamedFile.id)
        selectedFileDetail = renamedFile
        selectedFileNoteWriteBlock = noteWriteBlock(for: renamedFile)
        detailErrorMapping = nil
        isDetailLoading = false
    }
}

private extension MainFileRenameState {
    func renamingState(fileID: Int64, targetCategory: String?) -> MainFileRenameState {
        guard let targetCategory else { return .renaming(fileID: fileID) }
        return .renamingFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
    }

    func failedState(
        fileID: Int64,
        targetCategory: String?,
        mapping: CoreErrorMappingSnapshot
    ) -> MainFileRenameState {
        guard let targetCategory else { return .failed(fileID: fileID, mapping) }
        return .failedFromChangeCategory(fileID: fileID, targetCategory: targetCategory, mapping)
    }
}

enum BatchRenameModeSnapshot: String, CaseIterable, Equatable, Identifiable {
    case prefix = "Prefix"
    case datePrefix = "Date prefix"
    case keepBaseSequence = "Keep base + sequence"
    case replaceText = "Replace text"

    var id: String { rawValue }
}

enum BatchRenameDateSourceSnapshot: String, CaseIterable, Equatable, Identifiable {
    case imported = "Imported"
    case modified = "Modified"
    case today = "Today"

    var id: String { rawValue }
}

struct BatchRenameRuleSnapshot: Equatable {
    var mode: BatchRenameModeSnapshot
    var prefix: String?
    var dateSource: BatchRenameDateSourceSnapshot?
    var dateFormat: String?
    var separator: String?
    var startNumber: Int64?
    var padding: Int64?
    var find: String?
    var replacement: String?
    var caseSensitive: Bool
}

enum BatchRenamePreviewStatusSnapshot: String, Equatable {
    case ok = "OK"
    case error = "ERROR"
    case nameConflict = "NAME"
    case missing = "MISSING"
    case readOnly = "READONLY"
    case displayOnly = "DISPLAY_ONLY"
    case unchanged = "UNCHANGED"
    case externalChange = "EXTERNAL_CHANGE"
}

struct BatchRenamePreviewItemSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var currentPath: String?
    var originalName: String?
    var newName: String?
    var targetPath: String?
    var status: BatchRenamePreviewStatusSnapshot
    var reason: String?

    var id: Int64 { fileID }
}

struct BatchRenamePreviewReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var rule: BatchRenameRuleSnapshot
    var previewToken: String
    var willRenameCount: Int64
    var displayOnlyCount: Int64
    var unchangedCount: Int64
    var blockedCount: Int64
    var conflictCount: Int64
    var items: [BatchRenamePreviewItemSnapshot]
    var canApply: Bool
    var applyBlockedReason: String?
}

enum BatchRenameResultStatusSnapshot: String, Equatable {
    case renamed = "Renamed"
    case displayNameUpdated = "Display name updated"
    case unchanged = "Unchanged"
    case skipped = "Skipped"
    case failed = "Failed"
}

struct BatchRenameItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var originalName: String?
    var finalName: String?
    var finalPath: String?
    var status: BatchRenameResultStatusSnapshot
    var error: String?

    var id: Int64 { fileID }
}

struct BatchRenameReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var renamedCount: Int64
    var displayNameUpdatedCount: Int64
    var unchangedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchRenameItemResultSnapshot]
    var updatedFiles: [FileEntrySnapshot]
    var undoToken: String?
}

enum BatchRenameRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
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
        if selectedFiles.isEmpty { return "No files selected" }
        if isReadOnly { return MainFileWriteActionDisabledReason.repoReadOnly.rawValue }
        if isLoading { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if selectedFiles.contains(where: { writeLockedFileIDs.contains($0.id) }) {
            return MainFileWriteActionDisabledReason.importLocked.rawValue
        }
        return nil
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

extension BatchRenameRuleSnapshot {
    init(coreRule: BatchRenameRule) {
        mode = BatchRenameModeSnapshot(coreRule.mode)
        prefix = coreRule.prefix
        dateSource = coreRule.dateSource.map(BatchRenameDateSourceSnapshot.init)
        dateFormat = coreRule.dateFormat
        separator = coreRule.separator
        startNumber = coreRule.startNumber
        padding = coreRule.padding
        find = coreRule.find
        replacement = coreRule.replacement
        caseSensitive = coreRule.caseSensitive
    }
}

extension BatchRenamePreviewItemSnapshot {
    init(_ coreItem: BatchRenamePreviewItem) {
        fileID = coreItem.fileId
        currentPath = coreItem.currentPath
        originalName = coreItem.originalName
        newName = coreItem.newName
        targetPath = coreItem.targetPath
        status = BatchRenamePreviewStatusSnapshot(coreItem.status)
        reason = coreItem.reason
    }
}

extension BatchRenameItemResultSnapshot {
    init(_ coreResult: BatchRenameItemResult) {
        fileID = coreResult.fileId
        originalName = coreResult.originalName
        finalName = coreResult.finalName
        finalPath = coreResult.finalPath
        status = BatchRenameResultStatusSnapshot(coreResult.status)
        error = coreResult.error
    }
}

private extension BatchRenameModeSnapshot {
    init(_ core: BatchRenameMode) {
        switch core {
        case .prefix: self = .prefix
        case .datePrefix: self = .datePrefix
        case .keepBaseSequence: self = .keepBaseSequence
        case .replaceText: self = .replaceText
        }
    }
}

private extension BatchRenameDateSourceSnapshot {
    init(_ core: BatchRenameDateSource) {
        switch core {
        case .imported: self = .imported
        case .modified: self = .modified
        case .today: self = .today
        }
    }
}

private extension BatchRenamePreviewStatusSnapshot {
    init(_ coreStatus: BatchRenamePreviewStatus) {
        switch coreStatus {
        case .ok: self = .ok
        case .error: self = .error
        case .nameConflict: self = .nameConflict
        case .missing: self = .missing
        case .readOnly: self = .readOnly
        case .displayOnly: self = .displayOnly
        case .unchanged: self = .unchanged
        case .externalChange: self = .externalChange
        }
    }
}

private extension BatchRenameResultStatusSnapshot {
    init(_ coreStatus: BatchRenameResultStatus) {
        switch coreStatus {
        case .renamed: self = .renamed
        case .displayNameUpdated: self = .displayNameUpdated
        case .unchanged: self = .unchanged
        case .skipped: self = .skipped
        case .failed: self = .failed
        }
    }
}
