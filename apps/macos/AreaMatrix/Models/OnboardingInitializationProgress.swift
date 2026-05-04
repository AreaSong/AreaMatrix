import Foundation

protocol CoreStartupRecovering: Sendable {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot
}

struct RecoveryReportSnapshot: Equatable, Sendable {
    var cleanedStagingFiles: Int64
    var revertedStagingDbRows: Int64
    var warnings: [String]

    var hasVisibleDetails: Bool {
        cleanedStagingFiles > 0 || revertedStagingDbRows > 0 || !warnings.isEmpty
    }
}

struct ReindexReportSnapshot: Equatable, Sendable {
    var scanSessionId: Int64?
    var inserted: Int64
    var updated: Int64
    var skipped: Int64
    var errors: [String]
}

struct RepositoryInitializationResult: Equatable, Sendable {
    var repoPath: String
    var mode: RepoInitModeSnapshot
    var scanSession: ScanSessionSnapshot?
    var recoveryReport: RecoveryReportSnapshot?
}

extension CoreBridge: CoreStartupRecovering {
    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(coreReport: try recoverCoreOnStartup(repoPath: repoPath))
    }
}

extension OnboardingModel {
    @MainActor
    func openInitializedRepository() {
        guard case .initializationDone(let result) = route else { return }
        route = .mainLoading(result.repoPath)
    }

    @MainActor
    func resumeInterruptedInitialization(repoPath: String, scanSession: ScanSessionSnapshot?) async {
        guard let scanSession else {
            route = .initializationFailed(repoPath, nil)
            return
        }

        let draft = RepositoryInitializationDraft(
            validation: Self.interruptedValidationSnapshot(repoPath: repoPath),
            mode: .adoptExisting,
            scanSession: scanSession
        )
        initializationScanSession = scanSession
        route = .initializing(draft)
        startInitializationProgressPolling(repoPath: repoPath, mode: .adoptExisting)
        defer { stopInitializationProgressPolling() }

        do {
            let report = try await scanSessionReader.resumeScanSession(
                repoPath: repoPath,
                scanSessionId: scanSession.id
            )
            initializationScanSession = Self.completedScanSession(scanSession, report: report)
            settingsWriter.saveConfiguredRepoPath(repoPath)
            route = .initializationDone(RepositoryInitializationResult(
                repoPath: repoPath,
                mode: .adoptExisting,
                scanSession: initializationScanSession,
                recoveryReport: initializationRecoveryReport
            ))
        } catch {
            await routeInitializationFailure(error, repoPath: repoPath)
        }
    }

    @MainActor
    func cleanUpInterruptedInitialization(repoPath: String) async {
        repositoryPathText = repoPath
        repositoryPathError = nil
        repositoryPathErrorMapping = nil

        do {
            try await recoverStartupResidue(repoPath: repoPath)
            let validation = try await pathValidator.validateRepoPath(repoPath: repoPath)
            repositoryPathValidation = validation
            latestScanSession = nil

            if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
                latestScanSession = try await scanSessionReader.latestScanSession(repoPath: validation.repoPath)
                route = .dbRepairConfirm(validation.repoPath, latestScanSession, nil)
                toastMessage = "仍检测到未完成的扫描，请 Resume 或选择其他资料库。"
                return
            }

            routeCleanRetryValidation(validation)
        } catch {
            await routeInitializationFailure(error, repoPath: repoPath)
        }
    }

    func initializeRepository(repoPath: String, mode: RepoInitModeSnapshot) async throws {
        switch mode {
        case .createEmpty:
            try await repositoryInitializer.initializeEmptyRepository(repoPath: repoPath)
        case .adoptExisting:
            try await repositoryInitializer.adoptExistingRepository(repoPath: repoPath)
        }
    }

    static func validationStillMatchesConfirmMode(
        _ validation: RepoPathValidationSnapshot,
        mode: RepoInitModeSnapshot
    ) -> Bool {
        guard validation.recommendedMode == mode, !validation.isInitialized else { return false }

        switch mode {
        case .createEmpty:
            return validation.isEmpty
        case .adoptExisting:
            return !validation.isEmpty
        }
    }

    func shouldLoadLatestScanSession(for validation: RepoPathValidationSnapshot) -> Bool {
        validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession)
    }

    @MainActor
    func startInitializationProgressPolling(repoPath: String, mode: RepoInitModeSnapshot) {
        stopInitializationProgressPolling()
        guard mode == .adoptExisting else { return }

        initializationProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshInitializationScanSession(repoPath: repoPath)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    @MainActor
    func stopInitializationProgressPolling() {
        initializationProgressTask?.cancel()
        initializationProgressTask = nil
    }

    @MainActor
    private func refreshInitializationScanSession(repoPath: String) async {
        guard isInitializingAdoptExisting(repoPath: repoPath) else { return }

        do {
            let session = try await scanSessionReader.latestScanSession(repoPath: repoPath)
            guard isInitializingAdoptExisting(repoPath: repoPath) else { return }
            initializationScanSession = session
            initializationProgressWarning = nil
        } catch {
            await recordInitializationProgressWarning(error, repoPath: repoPath)
        }
    }

    @MainActor
    private func recordInitializationProgressWarning(_ error: Error, repoPath: String) async {
        guard isInitializingAdoptExisting(repoPath: repoPath) else { return }

        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            guard isInitializingAdoptExisting(repoPath: repoPath) else { return }
            initializationProgressWarning = "无法读取接管进度：\(mapping.userMessage)"
        } else {
            initializationProgressWarning = "无法读取接管进度：\(error.localizedDescription)"
        }
    }

    private func isInitializingAdoptExisting(repoPath: String) -> Bool {
        guard case .initializing(let draft) = route else { return false }
        return draft.mode == .adoptExisting && draft.validation.repoPath == repoPath
    }

    @MainActor
    func recoverStartupResidue(repoPath: String) async throws {
        do {
            let report = try await startupRecoverer.recoverOnStartup(repoPath: repoPath)
            initializationRecoveryReport = report.hasVisibleDetails ? report : nil
        } catch CoreError.RepoNotInitialized(_) {
            initializationRecoveryReport = nil
        }
    }

    @MainActor
    private func routeCleanRetryValidation(_ validation: RepoPathValidationSnapshot) {
        repositoryPathError = validatePathBlockingMessage(for: validation)
        guard repositoryPathError == nil else {
            route = .validatePath
            return
        }

        if validation.isInitialized {
            openExistingRepository(validation)
            return
        }

        route = .confirmRepositoryInitialization(RepositoryInitializationDraft(
            validation: validation,
            mode: validation.recommendedMode ?? .adoptExisting,
            scanSession: nil
        ))
    }

    private static func interruptedValidationSnapshot(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: true,
            availableCapacityBytes: nil,
            isExternalVolume: nil,
            recommendedMode: .adoptExisting,
            issues: [.unfinishedScanSession]
        )
    }

    private static func completedScanSession(
        _ session: ScanSessionSnapshot,
        report: ReindexReportSnapshot
    ) -> ScanSessionSnapshot {
        let finishedAt = Int64(Date().timeIntervalSince1970)
        return ScanSessionSnapshot(
            id: report.scanSessionId ?? session.id,
            kind: session.kind,
            status: .completed,
            lastPath: session.lastPath,
            inserted: report.inserted,
            updated: report.updated,
            skipped: report.skipped,
            startedAt: session.startedAt,
            updatedAt: finishedAt,
            finishedAt: finishedAt,
            errors: report.errors
        )
    }
}

private extension RecoveryReportSnapshot {
    init(coreReport: RecoveryReport) {
        cleanedStagingFiles = coreReport.cleanedStagingFiles
        revertedStagingDbRows = coreReport.revertedStagingDbRows
        warnings = coreReport.warnings
    }
}

extension ReindexReportSnapshot {
    init(coreReport: ReindexReport) {
        scanSessionId = coreReport.scanSessionId
        inserted = coreReport.inserted
        updated = coreReport.updated
        skipped = coreReport.skipped
        errors = coreReport.errors
    }
}

private func recoverCoreOnStartup(repoPath: String) throws -> RecoveryReport {
    try recoverOnStartup(repoPath: repoPath)
}
