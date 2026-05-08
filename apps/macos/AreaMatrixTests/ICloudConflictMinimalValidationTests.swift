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
    func testS125C101FailureKeepsApplyDisabled() async {
        let validator = ICloudConflictRecordingPathValidator(
            result: .failure(CoreError.ICloudPlaceholder(path: "/tmp/repo/docs/report.pdf.icloud"))
        )
        let model = ICloudConflictMinimalModel.fixture(repoPath: "/tmp/repo", validator: validator)

        await model.validateRepositoryPath()

        guard case .failed(let failure) = model.repositoryValidationState else {
            return XCTFail("expected failed repository validation")
        }

        XCTAssertEqual(failure.title, "iCloud item is not downloaded")
        XCTAssertEqual(failure.message, "/tmp/repo/docs/report.pdf.icloud")
        XCTAssertFalse(model.canApplyKeepBoth)
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
        validator: any CoreRepositoryPathValidating
    ) -> ICloudConflictMinimalModel {
        ICloudConflictMinimalModel(
            repoPath: repoPath,
            originalVersion: .original(path: "\(repoPath)/docs/report.pdf"),
            conflictedCopyVersion: .conflictedCopy(path: "\(repoPath)/docs/report (Conflicted Copy).pdf"),
            pathValidator: validator
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
