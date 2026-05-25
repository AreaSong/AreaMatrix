import Foundation

protocol CoreFileImporting: Sendable {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot
}

protocol CoreBatchCopyImporting: Sendable {
    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot
}

protocol CoreImportConflictBatching: Sendable {
    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot
}

struct CoreBatchImportRequest {
    var repoPath: String
    var sourceURL: URL
    var storageMode: ImportSingleFileStorageMode
    var destination: ImportEntryDestination
    var suggestedCategory: String?
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy
}

extension CoreFileImporting {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importCopiedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importMovedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importIndexedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }
}

extension CoreBatchCopyImporting {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importCopiedFile(request: CoreBatchImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            storageMode: .copy,
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        ))
    }
}

extension CoreBridge: CoreFileImporting, CoreBatchCopyImporting {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .copied,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        )
    }

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            options: ImportOptions(
                mode: .copied,
                destination: coreImportDestination(for: request.destination),
                targetDirectory: coreImportTargetDirectory(for: request.destination),
                overrideCategory: coreImportCategoryOverride(
                    for: request.destination,
                    suggestedCategory: request.suggestedCategory
                ),
                overrideFilename: request.overrideFilename,
                duplicateStrategy: request.duplicateStrategy
            )
        )
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        switch request.storageMode {
        case .copy:
            try await importCopiedFile(request: request)
        case .indexOnly:
            try await importFile(
                repoPath: request.repoPath,
                sourceURL: request.sourceURL,
                options: ImportOptions(
                    mode: .indexed,
                    destination: coreImportDestination(for: request.destination),
                    targetDirectory: coreImportTargetDirectory(for: request.destination),
                    overrideCategory: coreImportCategoryOverride(
                        for: request.destination,
                        suggestedCategory: request.suggestedCategory
                    ),
                    overrideFilename: request.overrideFilename,
                    duplicateStrategy: request.duplicateStrategy
                )
            )
        case .move:
            try await importFile(
                repoPath: request.repoPath,
                sourceURL: request.sourceURL,
                options: ImportOptions(
                    mode: .moved,
                    destination: coreImportDestination(for: request.destination),
                    targetDirectory: coreImportTargetDirectory(for: request.destination),
                    overrideCategory: coreImportCategoryOverride(
                        for: request.destination,
                        suggestedCategory: request.suggestedCategory
                    ),
                    overrideFilename: request.overrideFilename,
                    duplicateStrategy: request.duplicateStrategy
                )
            )
        }
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .moved,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        )
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .indexed,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        )
    }

    private func importFile(
        repoPath: String,
        sourceURL: URL,
        options: ImportOptions
    ) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.importFile(repoPath: repoPath, sourcePath: sourceURL.path, options: options)
        }.value
        return FileEntrySnapshot(coreEntry: entry) { _, _ in .available }
    }
}

extension CoreBridge: CoreImportConflictBatching {
    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ImportConflictBatchPreviewReportSnapshot(coreReport: AreaMatrix.previewImportConflictBatch(
                repoPath: repoPath,
                request: ImportConflictBatchPreviewRequest(snapshot: request)
            ))
        }.value
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ImportConflictBatchApplyReportSnapshot(coreReport: AreaMatrix.applyImportConflictBatch(
                repoPath: repoPath,
                request: ImportConflictBatchApplyRequest(snapshot: request),
                previewToken: previewToken
            ))
        }.value
    }
}

private func coreImportDestination(for destination: ImportEntryDestination) -> ImportDestination {
    switch destination {
    case .autoClassify:
        .autoClassify
    case .category:
        .category
    case .repositoryRoot:
        .selectedDirectory
    }
}

private func coreImportTargetDirectory(for destination: ImportEntryDestination) -> String? {
    switch destination {
    case .autoClassify, .category:
        nil
    case .repositoryRoot:
        ""
    }
}

private func coreImportCategoryOverride(
    for destination: ImportEntryDestination,
    suggestedCategory: String?
) -> String? {
    switch destination {
    case .autoClassify:
        suggestedCategory
    case let .category(slug):
        slug
    case .repositoryRoot:
        nil
    }
}

private extension ImportConflictBatchPreviewRequest {
    init(snapshot: ImportConflictBatchPreviewRequestSnapshot) {
        self.init(
            importSessionId: snapshot.importSessionID,
            conflictIds: snapshot.conflictIDs,
            duplicateStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.duplicateStrategy),
            sameNameStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.sameNameStrategy),
            applyToAllSimilarConflicts: snapshot.applyToAllSimilarConflicts
        )
    }
}

private extension ImportConflictBatchApplyRequest {
    init(snapshot: ImportConflictBatchApplyRequestSnapshot) {
        self.init(
            importSessionId: snapshot.importSessionID,
            conflictIds: snapshot.conflictIDs,
            duplicateStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.duplicateStrategy),
            sameNameStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.sameNameStrategy),
            applyToAllSimilarConflicts: snapshot.applyToAllSimilarConflicts,
            replaceConfirmed: snapshot.replaceConfirmed
        )
    }
}

private extension ImportConflictBatchStrategy {
    init(snapshotValue: ImportConflictBatchStrategySnapshot) {
        switch snapshotValue {
        case .skip:
            self = .skip
        case .keepBoth:
            self = .keepBoth
        case .replace:
            self = .replace
        case .askPerItem:
            self = .askPerItem
        }
    }
}

private extension ImportConflictBatchStrategySnapshot {
    init(coreStrategy: ImportConflictBatchStrategy) {
        switch coreStrategy {
        case .skip:
            self = .skip
        case .keepBoth:
            self = .keepBoth
        case .replace:
            self = .replace
        case .askPerItem:
            self = .askPerItem
        }
    }
}

private extension ImportConflictBatchPreviewReportSnapshot {
    init(coreReport: ImportConflictBatchPreviewReport) {
        importSessionID = coreReport.importSessionId
        previewToken = coreReport.previewToken
        applyToAllSimilarConflicts = coreReport.applyToAllSimilarConflicts
        requestedConflictCount = coreReport.requestedConflictCount
        duplicateConflictCount = coreReport.duplicateConflictCount
        sameNameConflictCount = coreReport.sameNameConflictCount
        includedCount = coreReport.includedCount
        pendingCount = coreReport.pendingCount
        blockedCount = coreReport.blockedCount
        replaceCount = coreReport.replaceCount
        skipCount = coreReport.skipCount
        keepBothCount = coreReport.keepBothCount
        askPerItemCount = coreReport.askPerItemCount
        trashAvailable = coreReport.trashAvailable
        undoAvailable = coreReport.undoAvailable
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
        replaceConfirmationRequired = coreReport.replaceConfirmationRequired
        replaceConfirmationSummary = coreReport.replaceConfirmationSummary
        items = coreReport.items.map(ImportConflictBatchPreviewItemSnapshot.init(coreItem:))
    }
}

private extension ImportConflictBatchPreviewItemSnapshot {
    init(coreItem: ImportConflictBatchPreviewItem) {
        conflictID = coreItem.conflictId
        conflictType = ImportConflictBatchConflictTypeSnapshot(coreType: coreItem.conflictType)
        existingFileID = coreItem.existingFileId
        existingPath = coreItem.existingPath
        incomingPath = coreItem.incomingPath
        targetPath = coreItem.targetPath
        selectedStrategy = ImportConflictBatchStrategySnapshot(coreStrategy: coreItem.selectedStrategy)
        status = ImportConflictBatchPreviewStatusSnapshot(coreStatus: coreItem.status)
        willReplace = coreItem.willReplace
        willKeepBoth = coreItem.willKeepBoth
        willSkip = coreItem.willSkip
        willAskPerItem = coreItem.willAskPerItem
        indexOnly = coreItem.indexOnly
        riskSummary = coreItem.riskSummary
        reason = coreItem.reason
    }
}

private extension ImportConflictBatchApplyReportSnapshot {
    init(coreReport: ImportConflictBatchApplyReport) {
        importSessionID = coreReport.importSessionId
        requestedConflictCount = coreReport.requestedConflictCount
        resolvedCount = coreReport.resolvedCount
        skippedCount = coreReport.skippedCount
        keptBothCount = coreReport.keptBothCount
        replacedCount = coreReport.replacedCount
        queuedForPerItemCount = coreReport.queuedForPerItemCount
        pendingCount = coreReport.pendingCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(ImportConflictBatchItemResultSnapshot.init(coreResult:))
        affectedFileIDs = coreReport.affectedFileIds
        undoToken = coreReport.undoToken
        changeLogActions = coreReport.changeLogActions
        failureSummary = coreReport.failureSummary
    }
}

private extension ImportConflictBatchItemResultSnapshot {
    init(coreResult: ImportConflictBatchItemResult) {
        conflictID = coreResult.conflictId
        conflictType = ImportConflictBatchConflictTypeSnapshot(coreType: coreResult.conflictType)
        appliedStrategy = ImportConflictBatchStrategySnapshot(coreStrategy: coreResult.appliedStrategy)
        status = ImportConflictBatchResultStatusSnapshot(coreStatus: coreResult.status)
        fileID = coreResult.fileId
        finalPath = coreResult.finalPath
        error = coreResult.error
    }
}

private extension ImportConflictBatchConflictTypeSnapshot {
    init(coreType: ImportConflictBatchConflictType) {
        switch coreType {
        case .duplicateHash:
            self = .duplicateHash
        case .sameNameDifferentContent:
            self = .sameNameDifferentContent
        }
    }
}

private extension ImportConflictBatchPreviewStatusSnapshot {
    init(coreStatus: ImportConflictBatchPreviewStatus) {
        switch coreStatus {
        case .ready:
            self = .ready
        case .pending:
            self = .pending
        case .needsConfirmation:
            self = .needsConfirmation
        case .blocked:
            self = .blocked
        case .failed:
            self = .failed
        }
    }
}

private extension ImportConflictBatchResultStatusSnapshot {
    init(coreStatus: ImportConflictBatchResultStatus) {
        switch coreStatus {
        case .skipped:
            self = .skipped
        case .keptBoth:
            self = .keptBoth
        case .replaced:
            self = .replaced
        case .queuedForPerItem:
            self = .queuedForPerItem
        case .pending:
            self = .pending
        case .failed:
            self = .failed
        }
    }
}
