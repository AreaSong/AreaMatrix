import Foundation

#if DEBUG
struct DeveloperImportScenarioServices: CoreCategoryPredicting, CoreFileImporting, CoreBatchCopyImporting,
    CoreImportConflictBatching, ImportBatchDuplicatePrechecking, ImportBatchNameConflictPrechecking,
    ImportFolderScanning, ImportFolderConflictPrechecking, ImportSingleFilePreflighting,
    SourcePreflightInspecting, ImportFileResourceAccessing, ICloudPlaceholderDownloading,
    ImportBatchCoreFileLoading, CoreUndoActionLogging {
    func isDirectory(_ url: URL) -> Bool {
        url.path.hasSuffix("/")
    }

    func isICloudPlaceholder(_ url: URL) -> Bool {
        url.path.hasSuffix(".icloud")
    }

    func fileSizeBytes(_: URL) -> Int64? {
        48128
    }

    func sha256Hex(for _: URL) throws -> String {
        "developer-import-hash"
    }

    func predictCategory(repoPath _: String, filename: String) async throws -> ClassifyResultSnapshot {
        DeveloperImportScenarioFixture.prediction(filename: filename)
    }

    func importCopiedFile(
        repoPath _: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot {
        importedFile(sourceURL, category: overrideCategory, filename: overrideFilename, mode: "Copied")
    }

    func importMovedFile(
        repoPath _: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot {
        importedFile(sourceURL, category: overrideCategory, filename: overrideFilename, mode: "Moved")
    }

    func importIndexedFile(
        repoPath _: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot {
        importedFile(sourceURL, category: overrideCategory, filename: overrideFilename, mode: "Indexed")
    }

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        importedFile(
            request.sourceURL,
            category: resolvedCategory(request),
            filename: request.overrideFilename,
            mode: "Copied"
        )
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        importedFile(
            request.sourceURL,
            category: resolvedCategory(request),
            filename: request.overrideFilename,
            mode: storageModeName(request.storageMode)
        )
    }

    func previewImportConflictBatch(
        repoPath _: String,
        request _: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        throw AppSemanticError.internalFailure(rawContext: "Developer import fixture has no conflict batch")
    }

    func applyImportConflictBatch(
        repoPath _: String,
        request _: ImportConflictBatchApplyRequestSnapshot,
        previewToken _: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        throw AppSemanticError.internalFailure(rawContext: "Developer import fixture has no conflict batch")
    }

    func precheckDuplicates(
        repoPath _: String,
        sourceURLs _: [URL],
        destination _: ImportBatchDestinationOption
    ) async -> [String: ImportBatchDuplicatePrecheckResult] {
        [:]
    }

    func precheckNameConflicts(
        repoPath _: String,
        rows _: [ImportBatchPreviewRow],
        destination _: ImportBatchDestinationOption
    ) async -> [String: ImportBatchNameConflictPrecheckResult] {
        [:]
    }

    func scanFolder(
        rootURL _: URL,
        includeHiddenFiles _: Bool,
        followSymlinks _: Bool
    ) async -> ImportFolderScanResult {
        ImportFolderScanResult(
            rows: DeveloperImportScenarioFixture.folderRows,
            folderCount: 2,
            skippedRules: [],
            errors: []
        )
    }

    func precheckFolderConflicts(
        repoPath _: String,
        rows _: [ImportFolderPreviewRow],
        destination _: ImportBatchDestinationOption
    ) async -> [String: ImportFolderConflictPrecheckResult] {
        [:]
    }

    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 48128,
            sourceModifiedAt: 1_778_738_400,
            hashSha256: "developer-import-preflight",
            targetRelativePath: "\(request.category)/\(request.targetFilename)",
            conflict: .none,
            keepBothTargetRelativePath: nil
        )
    }

    func inspect(sourceURL _: URL) throws -> SourcePreflightSnapshot {
        SourcePreflightSnapshot(sizeBytes: 48128, modifiedAt: 1_778_738_400)
    }

    func downloadPlaceholder(at _: URL) async throws {}

    func loadImportPreviewFiles(repoPath _: String, categories _: Set<String?>) async throws -> [FileEntrySnapshot] {
        []
    }

    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        []
    }

    func undoAction(repoPath _: String, actionID _: String) async throws -> UndoActionResultSnapshot {
        throw AppSemanticError.internalFailure(rawContext: "Developer import fixture has no undo action")
    }

    private func importedFile(
        _ sourceURL: URL,
        category: String,
        filename: String,
        mode: String
    ) -> FileEntrySnapshot {
        DeveloperImportScenarioFixture.importedFile(
            filename: filename.isEmpty ? sourceURL.lastPathComponent : filename,
            category: category.isEmpty ? "inbox" : category,
            storageMode: mode
        )
    }

    private func resolvedCategory(_ request: CoreBatchImportRequest) -> String {
        switch request.destination {
        case .autoClassify:
            request.suggestedCategory ?? "inbox"
        case let .category(category):
            category
        case .repositoryRoot:
            "inbox"
        }
    }

    private func storageModeName(_ mode: ImportSingleFileStorageMode) -> String {
        switch mode {
        case .copy: "Copied"
        case .move: "Moved"
        case .indexOnly: "Indexed"
        }
    }
}

actor DeveloperImportScenarioSessionStore: ImportBatchSessionPersisting {
    private var session: ImportBatchSessionSnapshot?

    func saveSession(_ session: ImportBatchSessionSnapshot) async {
        self.session = session
    }

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        guard session?.repoPath == repoPath else { return nil }
        return session
    }

    func clearSession(repoPath: String) async {
        guard session?.repoPath == repoPath else { return }
        session = nil
    }
}
#endif
