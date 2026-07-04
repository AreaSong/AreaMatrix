@testable import AreaMatrix
import Foundation

func importConflictDuplicatePreflight() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 12,
        hashSha256: "same-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .duplicate(existingPath: "docs/existing-source.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf"
    )
}

func importConflictNamePreflight() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 12,
        hashSha256: "different-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .name(path: "docs/source.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf",
        existingPaths: ["docs/source.pdf"]
    )
}

func importConflictBatchRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: true,
        isTrashAvailable: true
    )
}

func importConflictBatchIntegrationRequest(urls: [URL], conflictIDs: [String]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .importConflictBatch(.importConflictBatch),
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: true,
        isTrashAvailable: true,
        importSessionID: "session-221",
        importConflictIDs: conflictIDs
    )
}

@MainActor
func importConflictBatchIntegrationModel(
    conflictBatcher: any CoreImportConflictBatching,
    undoStore: any CoreUndoActionLogging
) -> ImportBatchCopyImportModel {
    ImportBatchCopyImportModel(
        importer: ImportBatchRecordingBatchImporter(),
        errorMapper: RecordingCoreErrorMapper.importSingleFile(),
        conflictBatcher: conflictBatcher,
        undoActionStore: undoStore
    )
}

actor ImportConflictBatcher: CoreImportConflictBatching {
    private var previews: [ImportConflictBatchPreviewReportSnapshot]
    private var recordedPreviewRequests: [ImportConflictPreviewRequest] = []
    private var recordedApplyRequests: [ImportConflictApplyRequest] = []

    init(previews: [ImportConflictBatchPreviewReportSnapshot]) {
        self.previews = previews
    }

    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        recordedPreviewRequests.append(ImportConflictPreviewRequest(
            repoPath: repoPath,
            request: request
        ))
        guard !previews.isEmpty else { throw CoreError.Conflict(path: "missing import-conflict-batch preview") }
        return previews.removeFirst().withImportConflictBatchRequest(request)
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        recordedApplyRequests.append(ImportConflictApplyRequest(
            repoPath: repoPath,
            request: request,
            previewToken: previewToken
        ))
        return .importConflictBatchIntegrationReport(for: request)
    }

    func previewRequests() -> [ImportConflictPreviewRequest] {
        recordedPreviewRequests
    }

    func applyRequests() -> [ImportConflictApplyRequest] {
        recordedApplyRequests
    }
}

func importConflictExpectedBatchRequests() -> [ImportBatchBatchImportRequest] {
    [
        ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "Invoice_2026Q1.pdf",
            duplicateStrategy: .overwrite
        ),
        ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "contract-renamed.pdf",
            duplicateStrategy: .keepBoth
        )
    ]
}

func importConflictProgressItems() -> [ImportBatchProgressSnapshot.Item] {
    [
        ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/imported.pdf",
            targetPath: "docs/imported.pdf",
            phase: .done,
            errorMessage: nil
        ),
        ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/failed.pdf",
            targetPath: "docs/failed.pdf",
            phase: .failed,
            errorMessage: "Storage write failed"
        ),
        ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/duplicate.pdf",
            targetPath: "finance/Invoice_2026Q1.pdf",
            phase: .pending,
            errorMessage: nil,
            existingRelativePath: "finance/Invoice_2026Q1.pdf"
        )
    ]
}
