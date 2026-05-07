import Foundation

extension OnboardingModel {
    @MainActor
    func chooseImportSources(opening: RepositoryOpeningResult) {
        guard let urls = importPicker.chooseImportURLs() else { return }
        startImportEntry(opening: opening, source: .filePicker, urls: urls)
    }

    @MainActor
    func startImportEntry(
        opening: RepositoryOpeningResult,
        source: ImportEntrySource,
        urls: [URL],
        destination: ImportEntryDestination = .autoClassify
    ) {
        let fileURLs = Self.validFileURLs(from: urls)
        guard !fileURLs.isEmpty else {
            toastMessage = "Cannot import these items"
            accessibilityAnnouncer.announce("Cannot import these items")
            return
        }

        pendingImportEntry = ImportEntryRequest(
            repoPath: opening.config.repoPath,
            source: source,
            destination: destination,
            urls: fileURLs,
            kind: ImportEntryKind.resolved(for: fileURLs),
            availableCategories: resolvedImportCategories(opening: opening, destination: destination),
            allowReplaceDuringImport: opening.config.allowReplaceDuringImport,
            isTrashAvailable: Self.isSystemTrashAvailable()
        )
        toastMessage = nil
    }

    @MainActor
    func dismissImportEntry() {
        pendingImportEntry = nil
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func switchImportEntryToLocalRepository() {
        pendingImportEntry = nil
        showChoosePath()
    }

    @MainActor
    func beginImportEntryProgress(currentPath: String) {
        beginImportEntryProgress(currentPath: currentPath, storageMode: .copy)
    }

    @MainActor
    func beginImportEntryProgress(currentPath: String, storageMode: ImportSingleFileStorageMode) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        pendingImportEntry = nil
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: currentPath,
            storageMode: storageMode
        ))
    }

    @MainActor
    func beginImportEntryProgress(
        currentPath: String,
        sourcePath: String,
        storageMode: ImportSingleFileStorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        let retryContext = ImportProgressRetryContext(
            repoPath: opening.config.repoPath,
            sourcePath: sourcePath,
            storageMode: storageMode,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: duplicateStrategy)
        )
        pendingImportEntry = nil
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: currentPath,
            storageMode: storageMode,
            retryContext: retryContext,
            isRepositoryFinderAvailable: FileManager.default.fileExists(atPath: opening.config.repoPath)
        ))
    }

    @MainActor
    func updateImportEntryProgress(_ progress: ImportBatchProgressSnapshot) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        pendingImportEntry = nil
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: progress.currentPath,
            status: .running,
            completed: progress.completed,
            failed: progress.failed,
            remaining: progress.remaining,
            skipped: progress.skipped,
            pending: progress.pending,
            items: progress.items
        ))
    }

    @MainActor
    func failImportEntry(currentPath: String, mapping: CoreErrorMappingSnapshot) {
        failImportEntry(
            progress: ImportBatchProgressSnapshot(
                completed: 0,
                failed: 1,
                total: 1,
                remaining: 0,
                currentPath: currentPath
            ),
            mapping: mapping
        )
    }

    @MainActor
    func failImportEntry(progress: ImportBatchProgressSnapshot, mapping: CoreErrorMappingSnapshot) {
        failImportEntry(progress: progress, mapping: mapping, retryContext: nil)
    }

    @MainActor
    func failImportEntry(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?,
        recoveryCheck: ImportProgressRecoveryCheckState
    ) {
        applyImportEntryFailure(
            progress: progress,
            mapping: mapping,
            retryContext: retryContext,
            recoveryCheck: recoveryCheck
        )
    }

    @MainActor
    func failImportEntry(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?
    ) {
        applyImportEntryFailure(progress: progress, mapping: mapping, retryContext: retryContext, recoveryCheck: nil)
    }

    @MainActor
    private func applyImportEntryFailure(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?,
        recoveryCheck: ImportProgressRecoveryCheckState?
    ) {
        guard case .importProgress(let state) = route else { return }
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: state.sourceOpening,
            currentPath: progress.currentPath,
            status: .failed(mapping),
            completed: progress.completed,
            failed: progress.failed,
            remaining: progress.remaining,
            skipped: progress.skipped,
            pending: progress.pending,
            items: progress.items,
            retryContext: retryContext ?? state.retryContext,
            recoveryCheck: recoveryCheck,
            diagnostics: state.diagnostics,
            stopState: state.stopState,
            isRepositoryFinderAvailable: state.isRepositoryFinderAvailable
        ))
    }

    @MainActor
    func showImportEntryExistingFile(relativePath: String) {
        guard let request = pendingImportEntry else { return }
        do {
            try fileRevealer.revealFile(repoPath: request.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = "Existing file cannot be shown in Finder."
        }
    }

    @MainActor
    func finishImportEntry(repoPath: String, entry: FileEntrySnapshot) async {
        do {
            let opening = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: repoPath)
            finishSuccessfulRepositoryOpen(opening)
            toastMessage = "已导入：\(entry.currentName)"
            accessibilityAnnouncer.announce("已导入：\(entry.currentName)")
        } catch {
            await routeMainOpeningFailure(error, repoPath: repoPath)
        }
    }

    @MainActor
    func returnFromImportProgress() {
        guard case .importProgress(let state) = route else { return }
        route = Self.mainRoute(for: state.sourceOpening)
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func handleDockOpenFiles(_ urls: [URL]) {
        let fileURLs = Self.validFileURLs(from: urls)
        guard !fileURLs.isEmpty else { return }
        queuedDockImportBatches.append(fileURLs)
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func consumePendingDockOpenRequests() {
        for urls in AreaMatrixDockOpenRelay.takePendingBatches() {
            handleDockOpenFiles(urls)
        }
    }

    @MainActor
    func consumeQueuedDockImportIfPossible() {
        guard pendingImportEntry == nil else { return }
        guard let opening = currentOpeningForImport else { return }
        guard queuedDockImportBatches.isEmpty == false else { return }
        let urls = queuedDockImportBatches.removeFirst()
        startImportEntry(opening: opening, source: .dockOpenFile, urls: urls)
    }

    private func resolvedImportCategories(
        opening: RepositoryOpeningResult,
        destination: ImportEntryDestination
    ) -> [String] {
        var categories = opening.availableImportCategories
        if case .category(let slug) = destination, !categories.contains(slug) {
            categories.append(slug)
        }
        return categories
    }

    private var currentOpeningForImport: RepositoryOpeningResult? {
        switch route {
        case .mainEmpty(let opening), .mainList(let opening):
            return opening
        default:
            return nil
        }
    }

    private var currentOpeningForImportOrProgress: RepositoryOpeningResult? {
        switch route {
        case .importProgress(let state):
            return state.sourceOpening
        default:
            return currentOpeningForImport
        }
    }

    func validatePathBlockingMessage(for validation: RepoPathValidationSnapshot) -> String? {
        let checks: [(Bool, String)] = [
            (
                validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix),
                "请选择资料库根目录，而不是 .areamatrix 内部目录"
            ),
            (
                !validation.exists || validation.issues.contains(.missingPath),
                "路径不存在，请选择已存在的文件夹"
            ),
            (!validation.isDirectory || validation.issues.contains(.notDirectory), "请选择文件夹路径"),
            (
                !validation.isReadable || validation.issues.contains(.notReadable),
                "AreaMatrix 没有读取该位置的权限"
            ),
            (
                !validation.isWritable || validation.issues.contains(.notWritable),
                "AreaMatrix 没有写入该位置的权限"
            ),
            (validation.hasInsufficientAvailableCapacity, "可用空间不足，请释放空间或选择其他路径"),
            (validation.hasMissingEnvironmentChecks, "路径环境检查缺失，请重试或选择其他路径"),
            (
                validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession),
                "该资料库存在未完成的扫描记录，请先进入修复流程"
            ),
            (
                validation.recommendedMode == nil && !validation.isInitialized,
                "该路径暂时不能作为资料库使用"
            ),
        ]

        return checks.first { $0.0 }?.1
    }

    func localRepositoryPathError(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return "请输入资料库路径" }
        if trimmed.contains("\0") { return "路径字符串无法解析" }
        if Self.pathContainsAreaMatrixComponent(trimmed) {
            return "请选择资料库根目录，而不是 .areamatrix 内部目录"
        }
        return nil
    }

    static func normalizedRepositoryPath(_ value: String) -> String {
        (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    static func pathContainsAreaMatrixComponent(_ value: String) -> Bool {
        let normalized = normalizedRepositoryPath(value)
        return normalized.split(separator: "/", omittingEmptySubsequences: true).contains(".areamatrix")
    }

    static func validFileURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            url.isFileURL && !url.path.isEmpty
        }
    }

    static func isSystemTrashAvailable() -> Bool {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).isEmpty == false
    }

}
