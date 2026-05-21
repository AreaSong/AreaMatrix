import Foundation

enum BatchChangeCategoryRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
    case commandPalette
}

struct BatchChangeCategoryRoute: Identifiable, Equatable {
    let source: BatchChangeCategoryRouteSource
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?

    var id: String {
        "\(source.rawValue):\(fileIDs.map(String.init).joined(separator: ",")):\(selectedCount):\(disabledReason ?? "")"
    }
}

struct BatchChangeCategoryApplyResult: Equatable {
    var report: BatchCategoryChangeReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchChangeCategoryNewCategoryHandoff: Equatable, Identifiable {
    var sourcePageID: String = "S2-12"
    var targetPageID: String = "S2-19"
    var selectedFileIDs: [Int64]
    var currentTargetCategory: String

    var id: String {
        "\(sourcePageID)-\(targetPageID)-\(selectedFileIDs.map(String.init).joined(separator: ","))"
    }
}

enum BatchChangeCategoryPreviewState: Equatable {
    case idle
    case loading(previous: BatchCategoryPreviewReportSnapshot?)
    case loaded(BatchCategoryPreviewReportSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: BatchCategoryPreviewReportSnapshot?)

    var report: BatchCategoryPreviewReportSnapshot? {
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

enum BatchChangeCategoryEntryPolicy {
    static func openHelp(disabledReason: String?) -> String {
        disabledReason.map { "\($0). You can still preview selected files and category impact." } ??
            "Change category for the selected files"
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

enum BatchChangeCategorySelection {
    static func availableCategories(
        selectedFiles: [FileEntrySnapshot],
        categoryRows: [RepositorySidebarRowSnapshot],
        createdCategories: [String] = []
    ) -> [String] {
        let sidebarCategories = categoryRows.compactMap(\.categoryForFileList)
        let selectedCategories = selectedFiles.map(\.category)
        let normalizedCreated = createdCategories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(sidebarCategories + selectedCategories + normalizedCreated)).sorted()
    }

    static func defaultTargetCategory(
        selectedFiles: [FileEntrySnapshot],
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        let currentCategories = Set(selectedFiles.map(\.category))
        return availableCategories(selectedFiles: selectedFiles, categoryRows: categoryRows)
            .first { !currentCategories.contains($0) } ?? selectedFiles.first?.category ?? ""
    }

    static func categoryDistributionText(selectedFiles: [FileEntrySnapshot]) -> String {
        let counts = Dictionary(grouping: selectedFiles, by: \.category)
            .mapValues { Int64($0.count) }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }
}

enum BatchChangeCategoryCreatedCategoryReturn {
    static func updatedCategories(_ categories: [String], savedCategory: String) -> [String] {
        let normalized = savedCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return categories }
        return BatchChangeCategorySelection.availableCategories(
            selectedFiles: [],
            categoryRows: [],
            createdCategories: categories + [normalized]
        )
    }
}

enum BatchChangeCategoryAction {
    static func preview(
        repoPath: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        changer: any CoreBatchCategoryChanging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchChangeCategoryPreviewState {
        do {
            let report = try await changer.previewBatchMoveToCategory(
                repoPath: repoPath,
                fileIDs: fileIDs,
                targetCategory: targetCategory,
                moveRepoOwnedFiles: moveRepoOwnedFiles
            )
            return .loaded(report)
        } catch {
            return .failed(await mapError(error, errorMapper: errorMapper), previous: nil)
        }
    }

    static func apply(
        repoPath: String,
        fileIDs: [Int64],
        preview: BatchCategoryPreviewReportSnapshot,
        changer: any CoreBatchCategoryChanging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchChangeCategoryApplyResult {
        do {
            let report = try await changer.batchMoveToCategory(
                repoPath: repoPath,
                fileIDs: fileIDs,
                targetCategory: preview.targetCategory,
                moveRepoOwnedFiles: preview.moveRepoOwnedFiles,
                previewToken: preview.previewToken
            )
            return BatchChangeCategoryApplyResult(report: report, failure: nil)
        } catch {
            return BatchChangeCategoryApplyResult(
                report: nil,
                failure: await mapError(error, errorMapper: errorMapper)
            )
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

enum BatchChangeCategoryValidation {
    static func canApply(
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        fileIDs: [Int64],
        preview: BatchCategoryPreviewReportSnapshot?,
        disabledReason: String?,
        isApplying: Bool
    ) -> Bool {
        guard !isApplying,
              disabledReason == nil,
              !targetCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !fileIDs.isEmpty,
              let preview,
              preview.canApply else { return false }
        return preview.targetCategory == targetCategory &&
            preview.moveRepoOwnedFiles == moveRepoOwnedFiles &&
            preview.requestedFileCount == Int64(Set(fileIDs).count) &&
            Set(preview.items.map(\.fileID)) == Set(fileIDs)
    }
}

extension BatchCategoryChangeReportSnapshot {
    var successfulChangeCount: Int64 {
        movedCount + metadataOnlyCount
    }

    var shouldRefreshConsumerAfterApply: Bool {
        successfulChangeCount > 0 || !updatedFiles.isEmpty || undoToken != nil
    }

    var shouldCloseSheetAfterApply: Bool {
        failedCount == 0
    }
}

struct BatchCategoryPreviewReportPresentation: Equatable {
    var moveSummaryText: String
    var metadataSummaryText: String
    var skippedSummaryText: String
    var blockedSummaryText: String

    init(report: BatchCategoryPreviewReportSnapshot) {
        moveSummaryText = "\(Self.fileText(report.willMoveCount)) will move"
        metadataSummaryText = "\(Self.fileText(report.metadataOnlyCount)) will update only"
        skippedSummaryText = "\(Self.fileText(report.skippedCount)) cannot move"
        blockedSummaryText = "\(Self.fileText(report.blockedCount)) blocked"
    }

    private static func fileText(_ count: Int64) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}

struct BatchCategoryChangeReportPresentation: Equatable {
    var changedSummaryText: String
    var skippedSummaryText: String
    var failedSummaryText: String

    init(report: BatchCategoryChangeReportSnapshot) {
        let changed = report.movedCount + report.metadataOnlyCount
        changedSummaryText = "\(Self.fileText(changed)) changed"
        skippedSummaryText = "\(Self.fileText(report.skippedCount + report.unchangedCount)) skipped or unchanged"
        failedSummaryText = "\(Self.fileText(report.failedCount)) failed"
    }

    private static func fileText(_ count: Int64) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}
