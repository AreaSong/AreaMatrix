@testable import AreaMatrix
import XCTest

final class ICloudConflictMinimalValidationTests: XCTestCase {
    @MainActor
    func testICloudConflictMinimalValidateRepoPathCoreValidationUsesCoreBridgeStateAndAllowsKeepBoth() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            isICloudPath: true,
            issues: [.alreadyInitialized, .iCloudPath],
            recommendedMode: nil
        )
        let validator = ICloudConflictRecordingPathValidator(result: .success(validation))
        let model = ICloudConflictMinimalModel.fixture(repoPath: "/tmp/repo", validator: validator)

        await model.validateRepositoryPath()
        let requestedPaths = await validator.requestedRepoPaths()

        XCTAssertEqual(requestedPaths, ["/tmp/repo"])
        XCTAssertEqual(
            model.repositoryValidationState,
            .ready(validation, warnings: ["Repository is in iCloud Drive; validation does not download placeholders."])
        )
        XCTAssertTrue(model.canApplyKeepBoth)
    }

    @MainActor
    func testICloudConflictMinimalValidateRepoPathCoreBlocksApplyWhenValidationRejectsRepositoryPath() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo/.areamatrix",
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: false,
            hasUnfinishedScanSession: true,
            issues: [.insideAreaMatrix, .unfinishedScanSession],
            recommendedMode: nil
        )
        let validator = ICloudConflictRecordingPathValidator(result: .success(validation))
        let model = ICloudConflictMinimalModel.fixture(repoPath: validation.repoPath, validator: validator)

        await model.validateRepositoryPath()

        guard case let .blocked(blockedValidation, reasons) = model.repositoryValidationState else {
            return XCTFail("expected blocked repository validation")
        }

        XCTAssertEqual(blockedValidation, validation)
        XCTAssertTrue(reasons.contains("Use the repository root, not the .areamatrix metadata folder."))
        XCTAssertTrue(reasons.contains("This folder is not an initialized AreaMatrix repository."))
        XCTAssertFalse(model.canApplyKeepBoth)
    }

    @MainActor
    func testICloudConflictMinimalErrorMappingCoreFailureMapsCoreErrorAndKeepsApplyDisabled() async {
        let mapping = CoreErrorMappingSnapshot.icloudConflictFixture(
            kind: .iCloudPlaceholder,
            rawContext: "/tmp/repo/docs/report.pdf.icloud"
        )
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(CoreError.ICloudPlaceholder(path: "/tmp/repo/docs/report.pdf.icloud"))
        )
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let model = ICloudConflictMinimalModel.fixture(
            repoPath: "/tmp/repo",
            validator: validator,
            errorMapper: errorMapper
        )

        await model.validateRepositoryPath()
        let mappedErrors = await errorMapper.recordedErrors()

        guard case let .failed(failure) = model.repositoryValidationState else {
            return XCTFail("expected failed repository validation")
        }

        XCTAssertEqual(mappedErrors, [CoreError.ICloudPlaceholder(path: "/tmp/repo/docs/report.pdf.icloud")])
        XCTAssertEqual(failure, mapping)
        XCTAssertFalse(model.canApplyKeepBoth)
    }

    @MainActor
    func testICloudConflictMinimalErrorMappingCoreNonCoreFailureMapsAsInternalError() async {
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(ICloudConflictTestError.staleConflictContext)
        )
        let errorMapper = StaticCoreErrorMapper(
            mapping: .icloudConflictFixture(kind: .internal, rawContext: "stale conflict context")
        )
        let model = ICloudConflictMinimalModel.fixture(
            repoPath: "/tmp/repo",
            validator: validator,
            errorMapper: errorMapper
        )

        await model.validateRepositoryPath()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Internal(message: "stale conflict context")])
        guard case let .failed(failure) = model.repositoryValidationState else {
            return XCTFail("expected failed repository validation")
        }
        XCTAssertEqual(failure.kind, .internal)
        XCTAssertFalse(model.canApplyKeepBoth)
    }

    @MainActor
    func testICloudConflictMinimalErrorMappingCoreSheetShowsMappedFailureAndRetryHook() async {
        let mapping = CoreErrorMappingSnapshot.icloudConflictFixture(
            kind: .permissionDenied,
            rawContext: "/tmp/repo"
        )
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))
        )
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let model = ICloudConflictMinimalModel.fixture(
            repoPath: "/tmp/repo",
            validator: validator,
            errorMapper: errorMapper
        )

        await model.validateRepositoryPath()
        let view = ICloudConflictMinimalSheet(
            model: model,
            resolutionCapability: .supported,
            isTrashAvailable: true,
            onCancel: {},
            onApply: { _ in },
            onCollectDiagnostics: {}
        )

        assertTestMirrorDescription(of: view.body, contains: [
            "icloud-conflict-minimal-error-mapping-error-mapping",
            "Repository check failed: PermissionDenied",
            "AreaMatrix cannot inspect this conflict source.",
            "Severity: High; Recoverability: UserActionRequired",
            "icloud-conflict-minimal-error-mapping-retry-repository-check"
        ])
    }

    @MainActor
    func testICloudConflictMinimalValidateRepoPathCoreDefaultCoreBridgeValidatesRepositoryWithoutMovingConflictFiles(
    ) async throws {
        let repoURL = try makeICloudConflictTemporaryDirectory(prefix: "repo")
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let originalURL = docsURL.appendingPathComponent("report.pdf")
        let conflictedURL = docsURL.appendingPathComponent("report (Conflicted Copy).pdf")
        let originalData = Data("original bytes".utf8)
        let conflictedData = Data("conflicted bytes".utf8)
        try originalData.write(to: originalURL)
        try conflictedData.write(to: conflictedURL)

        let model = ICloudConflictMinimalModel(
            repoPath: repoURL.path,
            originalVersion: .original(path: originalURL.path),
            conflictedCopyVersion: .conflictedCopy(path: conflictedURL.path),
            conflictReviewer: nil
        )

        await model.validateRepositoryPath()

        XCTAssertTrue(model.canApplyKeepBoth)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertEqual(try Data(contentsOf: conflictedURL), conflictedData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictedURL.path))
    }

    @MainActor
    func testICloudConflictVisualICloudConflictVisualCorePreviewFailureMapsErrorAndKeepsResolutionDisabled() async {
        let mapper = StaticCoreErrorMapper(mapping: .icloudConflictFixture(
            kind: .conflict,
            rawContext: "stale conflict id"
        ))
        let reviewer = ICloudConflictReviewer(
            previewResult: .failure(CoreError.Conflict(path: "stale conflict id")),
            resolveResult: .success(.iCloudConflictVisualResolvedReport(conflictID: "stale"))
        )
        let model = ICloudConflictMinimalModel(
            repoPath: "/tmp/repo",
            conflictID: "stale",
            originalVersion: .original(path: "/tmp/repo/docs/report.pdf"),
            conflictedCopyVersion: .conflictedCopy(path: "/tmp/repo/docs/report (copy).pdf"),
            pathValidator: ICloudConflictRecordingPathValidator(result: .success(
                .iCloudConflictMinimalICloudConflictFixture().with(repoPath: "/tmp/repo")
            )),
            conflictReviewer: reviewer,
            errorMapper: mapper
        )

        await model.validateRepositoryPath()
        await model.loadPreview()
        assertTestMirrorDescription(of: ICloudConflictMinimalSheet(
            model: model,
            resolutionCapability: .supported,
            isTrashAvailable: true,
            onCancel: {},
            onApply: { _ in XCTFail("Preview failure must keep Apply unavailable") },
            onCollectDiagnostics: {}
        ).body, contains: [
            "icloud-conflict-review-icloud-conflict-visual-preview-error",
            "Conflict detail failed: Conflict",
            "Retry"
        ])
        let previewRequests = await reviewer.recordedPreviewRequests()
        let resolveRequests = await reviewer.recordedResolveRequests()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(previewRequests, [ICloudConflictReviewer.PreviewRequest(
            repoPath: "/tmp/repo",
            conflictID: "stale"
        )])
        XCTAssertEqual(resolveRequests, [])
        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "stale conflict id")])
        XCTAssertFalse(model.canApply(strategy: .keepBoth, isTrashAvailable: true, didConfirmSingleVersion: false))
    }

    @MainActor
    func testICloudConflictVisualICloudConflictVisualCoreKeepBothResolveCallsReviewerAndReturnsReport() async {
        let reviewer = ICloudConflictReviewer(
            previewResult: .success(.iCloudConflictVisualPreview(conflictID: "conflict-1")),
            resolveResult: .success(.iCloudConflictVisualResolvedReport(conflictID: "conflict-1"))
        )
        let model = ICloudConflictMinimalModel(
            repoPath: "/tmp/repo",
            conflictID: "conflict-1",
            originalVersion: .original(path: "/tmp/repo/docs/report.pdf"),
            conflictedCopyVersion: .conflictedCopy(path: "/tmp/repo/docs/report (copy).pdf"),
            pathValidator: ICloudConflictRecordingPathValidator(result: .success(
                .iCloudConflictMinimalICloudConflictFixture().with(repoPath: "/tmp/repo")
            )),
            conflictReviewer: reviewer,
            errorMapper: StaticCoreErrorMapper(mapping: .icloudConflictFixture(kind: .internal))
        )

        await model.validateRepositoryPath()
        await model.loadPreview()
        let result = await model.resolveConflict(strategy: .keepBoth)
        let resolveRequests = await reviewer.recordedResolveRequests()

        XCTAssertEqual(resolveRequests, [ICloudConflictReviewer.ResolveRequest(
            repoPath: "/tmp/repo",
            conflictID: "conflict-1",
            strategy: .keepBoth
        )])
        XCTAssertEqual(result, .resolved(ICloudConflictResolutionResult(
            focusFileID: nil,
            conflictID: "conflict-1",
            report: .iCloudConflictVisualResolvedReport(conflictID: "conflict-1"),
            status: .resolved,
            keptPaths: [
                "docs/report.pdf",
                "docs/report (copy).pdf"
            ],
            trashedPaths: [],
            undoToken: nil,
            changeLogAction: "external_modified",
            didClearConflictState: true,
            didWriteChangeLog: true
        )))
    }

    @MainActor
    func testICloudConflictVisualICloudConflictVisualCoreDefaultCoreBridgePreviewsAndKeepsBothVersionsWithoutFileMoves(
    ) async throws {
        let repoURL = try makeICloudConflictTemporaryDirectory(prefix: "iCloudConflictVisual-core")
        defer { removeTestTemporaryItems(repoURL) }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let originalURL = docsURL.appendingPathComponent("report.pdf")
        let conflictedURL = docsURL.appendingPathComponent("report (Alice's conflicted copy).pdf")
        let originalData = Data("original conflict bytes".utf8)
        let conflictedData = Data("conflicted copy bytes".utf8)
        try originalData.write(to: originalURL)
        try conflictedData.write(to: conflictedURL)

        let model = ICloudConflictMinimalModel(
            repoPath: repoURL.path,
            conflictID: "docs/report (Alice's conflicted copy).pdf",
            originalVersion: .original(path: originalURL.path),
            conflictedCopyVersion: .conflictedCopy(path: conflictedURL.path),
            conflictReviewer: CoreBridge()
        )

        await model.validateRepositoryPath()
        await model.loadPreview()
        let result = await model.resolveConflict(strategy: .keepBoth)

        guard case let .resolved(resolution) = result else {
            return XCTFail("Expected KeepBoth to resolve through the default CoreBridge")
        }
        XCTAssertEqual(model.previewState.preview?.conflictID, "docs/report (Alice's conflicted copy).pdf")
        XCTAssertEqual(model.previewState.preview?.defaultResolution, .keepBoth)
        XCTAssertTrue(model.canApply(strategy: .keepBoth, isTrashAvailable: true, didConfirmSingleVersion: false))
        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertEqual(resolution.trashedPaths, [])
        XCTAssertEqual(Set(resolution.keptPaths), [
            "docs/report.pdf",
            "docs/report (Alice's conflicted copy).pdf"
        ])
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertEqual(try Data(contentsOf: conflictedURL), conflictedData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictedURL.path))
    }
}

private typealias ICloudConflictRecordingPathValidator = RecordingRepositoryPathValidator

private extension ICloudConflictMinimalModel {
    static func fixture(
        repoPath: String,
        validator: any CoreRepositoryPathValidating,
        errorMapper: any CoreErrorMapping = StaticCoreErrorMapper(mapping: .icloudConflictFixture())
    ) -> ICloudConflictMinimalModel {
        ICloudConflictMinimalModel(
            repoPath: repoPath,
            originalVersion: .original(path: "\(repoPath)/docs/report.pdf"),
            conflictedCopyVersion: .conflictedCopy(path: "\(repoPath)/docs/report (Conflicted Copy).pdf"),
            pathValidator: validator,
            conflictReviewer: nil,
            errorMapper: errorMapper
        )
    }
}

private extension ICloudConflictVersionSnapshot {
    static func original(path: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot.testFixture(
            role: .original,
            path: path,
            sizeBytes: 512
        )
    }

    static func conflictedCopy(path: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot.testFixture(
            role: .conflictedCopy,
            path: path,
            modifiedAt: 1_775_020_860,
            sizeBytes: 768
        )
    }
}

private extension RepoPathValidationSnapshot {
    func with(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.exists = exists
            $0.isDirectory = isDirectory
            $0.isReadable = isReadable
            $0.isWritable = isWritable
            $0.isEmpty = isEmpty
            $0.isInitialized = isInitialized
            $0.isInsideAreaMatrix = isInsideAreaMatrix
            $0.isICloudPath = isICloudPath
            $0.hasUnfinishedScanSession = hasUnfinishedScanSession
            $0.availableCapacityBytes = availableCapacityBytes
            $0.isExternalVolume = isExternalVolume
            $0.recommendedMode = recommendedMode
            $0.issues = issues
        }
    }
}

private func makeICloudConflictTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixICloudConflict")
}

private enum ICloudConflictTestError: LocalizedError {
    case staleConflictContext

    var errorDescription: String? {
        "stale conflict context"
    }
}

private extension CoreErrorMappingSnapshot {
    static func icloudConflictFixture(
        kind: CoreErrorKindSnapshot = .iCloudPlaceholder,
        rawContext: String = "/tmp/repo/docs/report.pdf.icloud"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this conflict source.",
            severity: .high,
            suggestedAction: "Refresh the conflict list or download the iCloud item in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}
