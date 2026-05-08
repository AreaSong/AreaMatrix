import XCTest
@testable import AreaMatrix

final class ICloudConflictMinimalValidationTests: XCTestCase {
    @MainActor
    func testS125C101ValidationUsesCoreBridgeStateAndAllowsKeepBoth() async {
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
    func testS125C101BlocksApplyWhenValidationRejectsRepositoryPath() async {
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

        guard case .blocked(let blockedValidation, let reasons) = model.repositoryValidationState else {
            return XCTFail("expected blocked repository validation")
        }

        XCTAssertEqual(blockedValidation, validation)
        XCTAssertTrue(reasons.contains("Use the repository root, not the .areamatrix metadata folder."))
        XCTAssertTrue(reasons.contains("This folder is not an initialized AreaMatrix repository."))
        XCTAssertFalse(model.canApplyKeepBoth)
    }

    @MainActor
    func testS125C121FailureMapsCoreErrorAndKeepsApplyDisabled() async {
        let mapping = CoreErrorMappingSnapshot.icloudConflictFixture(
            kind: .iCloudPlaceholder,
            rawContext: "/tmp/repo/docs/report.pdf.icloud"
        )
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(CoreError.ICloudPlaceholder(path: "/tmp/repo/docs/report.pdf.icloud"))
        )
        let errorMapper = ICloudConflictRecordingErrorMapper(mapping: mapping)
        let model = ICloudConflictMinimalModel.fixture(
            repoPath: "/tmp/repo",
            validator: validator,
            errorMapper: errorMapper
        )

        await model.validateRepositoryPath()
        let mappedErrors = await errorMapper.recordedErrors()

        guard case .failed(let failure) = model.repositoryValidationState else {
            return XCTFail("expected failed repository validation")
        }

        XCTAssertEqual(mappedErrors, [CoreError.ICloudPlaceholder(path: "/tmp/repo/docs/report.pdf.icloud")])
        XCTAssertEqual(failure, mapping)
        XCTAssertFalse(model.canApplyKeepBoth)
    }

    @MainActor
    func testS125C121NonCoreFailureMapsAsInternalError() async {
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(ICloudConflictTestError.staleConflictContext)
        )
        let errorMapper = ICloudConflictRecordingErrorMapper(
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
        guard case .failed(let failure) = model.repositoryValidationState else {
            return XCTFail("expected failed repository validation")
        }
        XCTAssertEqual(failure.kind, .internal)
        XCTAssertFalse(model.canApplyKeepBoth)
    }

    @MainActor
    func testS125C121SheetShowsMappedFailureAndRetryHook() async {
        let mapping = CoreErrorMappingSnapshot.icloudConflictFixture(
            kind: .permissionDenied,
            rawContext: "/tmp/repo"
        )
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))
        )
        let errorMapper = ICloudConflictRecordingErrorMapper(mapping: mapping)
        let model = ICloudConflictMinimalModel.fixture(
            repoPath: "/tmp/repo",
            validator: validator,
            errorMapper: errorMapper
        )

        await model.validateRepositoryPath()
        let view = ICloudConflictMinimalSheet(
            model: model,
            isTrashAvailable: true,
            onCancel: {},
            onApplyKeepBoth: {}
        )
        let body = s125MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("S1-25-C1-21-error-mapping"))
        XCTAssertTrue(body.contains("Repository check failed: PermissionDenied"))
        XCTAssertTrue(body.contains("AreaMatrix cannot inspect this conflict source."))
        XCTAssertTrue(body.contains("Severity: High; Recoverability: UserActionRequired"))
        XCTAssertTrue(body.contains("S1-25-C1-21-retry-repository-check"))
    }

    @MainActor
    func testS125C101DefaultCoreBridgeValidatesRepositoryWithoutMovingConflictFiles() async throws {
        let repoURL = try makeICloudConflictTemporaryDirectory(prefix: "repo")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }
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
            conflictedCopyVersion: .conflictedCopy(path: conflictedURL.path)
        )

        await model.validateRepositoryPath()

        XCTAssertTrue(model.canApplyKeepBoth)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertEqual(try Data(contentsOf: conflictedURL), conflictedData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictedURL.path))
    }
}

private actor ICloudConflictRecordingPathValidator: CoreRepositoryPathValidating {
    private let result: Result<RepoPathValidationSnapshot, Error>
    private var repoPaths: [String] = []

    init(result: Result<RepoPathValidationSnapshot, Error>) {
        self.result = result
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        repoPaths.append(repoPath)
        return try result.get()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

private extension ICloudConflictMinimalModel {
    static func fixture(
        repoPath: String,
        validator: any CoreRepositoryPathValidating,
        errorMapper: any CoreErrorMapping = ICloudConflictRecordingErrorMapper(mapping: .icloudConflictFixture())
    ) -> ICloudConflictMinimalModel {
        ICloudConflictMinimalModel(
            repoPath: repoPath,
            originalVersion: .original(path: "\(repoPath)/docs/report.pdf"),
            conflictedCopyVersion: .conflictedCopy(path: "\(repoPath)/docs/report (Conflicted Copy).pdf"),
            pathValidator: validator,
            errorMapper: errorMapper
        )
    }
}

private extension ICloudConflictVersionSnapshot {
    static func original(path: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .original,
            path: path,
            modifiedAt: 1_775_020_800,
            sizeBytes: 512
        )
    }

    static func conflictedCopy(path: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .conflictedCopy,
            path: path,
            modifiedAt: 1_775_020_860,
            sizeBytes: 768
        )
    }
}

private func makeICloudConflictTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixICloudConflict-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private enum ICloudConflictTestError: LocalizedError {
    case staleConflictContext

    var errorDescription: String? {
        "stale conflict context"
    }
}

private actor ICloudConflictRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

private extension CoreErrorMappingSnapshot {
    static func icloudConflictFixture(
        kind: CoreErrorKindSnapshot = .iCloudPlaceholder,
        rawContext: String = "/tmp/repo/docs/report.pdf.icloud"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this conflict source.",
            severity: .high,
            suggestedAction: "Refresh the conflict list or download the iCloud item in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}

private func s125MirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS125MirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS125MirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS125MirrorDescription(of: child.value, to: &lines)
    }
}
