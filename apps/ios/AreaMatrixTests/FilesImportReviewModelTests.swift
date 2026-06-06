@testable import AreaMatrixIOS
import Foundation
import XCTest

@MainActor
final class FilesImportReviewModelTests: XCTestCase {
    func testPrepareBuildsPreviewAndUsesCorePrediction() async throws {
        let source = try makeSelectedFile(name: "Receipt.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(prediction: .fixture(category: "receipts"))
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )

        await model.prepare()

        let predictions = await bridge.predictionRequestsSnapshot()
        XCTAssertEqual(predictions.map(\.filename), ["Receipt.pdf"])
        XCTAssertEqual(model.category, "receipts")
        XCTAssertEqual(model.filename, "Receipt.pdf")
        XCTAssertEqual(model.previewItems.map(\.status), [.ready])
        XCTAssertTrue(model.canImport)
    }

    func testEmptySelectionDoesNotCallCore() async {
        let bridge = FakeFilesImportCoreBridge(prediction: .fixture(category: "inbox"))
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )

        await model.prepare()

        let predictions = await bridge.predictionRequestsSnapshot()
        XCTAssertTrue(predictions.isEmpty)
        XCTAssertEqual(model.error, .emptySelection)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertFalse(model.canImport)
    }

    func testImportUsesCopiedFilesRequestThroughCoreBridge() async throws {
        let source = try makeSelectedFile(name: "Notes.txt")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(prediction: .fixture(category: "docs"))
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )

        await model.prepare()
        await model.importFiles()

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports.first?.repoPath, "/tmp/Repo")
        XCTAssertEqual(imports.first?.sourceURL, source)
        XCTAssertEqual(imports.first?.filename, "Notes.txt")
        XCTAssertEqual(imports.first?.category, "docs")
        XCTAssertEqual(imports.first?.duplicateStrategy, .skip)
        XCTAssertEqual(model.importedFiles.map(\.currentName), ["Notes.txt"])
        XCTAssertEqual(model.phase, .succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testDuplicateContentUsesSkipDefaultWithoutDeletingSource() async throws {
        let source = try makeSelectedFile(name: "Existing.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(
            prediction: .fixture(category: "docs"),
            importErrors: [.duplicateContent("docs/Existing.pdf")]
        )
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )

        await model.prepare()
        await model.importFiles()

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip])
        let candidate = try XCTUnwrap(model.replaceCandidates.first)
        XCTAssertEqual(candidate.kind, .duplicateContent)
        XCTAssertEqual(model.previewItems.map(\.status), [.failed("Duplicate content: docs/Existing.pdf")])
        model.updateConflictStrategy(for: candidate.id, strategy: .skip)
        try await waitForSucceededPhase(model)
        XCTAssertEqual(model.previewItems.map(\.status), [.skippedDuplicate("docs/Existing.pdf")])
        XCTAssertEqual(model.phase, .succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testNameConflictRetriesWithKeepBothFilename() async throws {
        let source = try makeSelectedFile(name: "Plan.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(
            prediction: .fixture(category: "docs"),
            importErrors: [.nameConflict("docs/Plan.pdf")]
        )
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )

        await model.prepare()
        await model.importFiles()

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip])
        let candidate = try XCTUnwrap(model.replaceCandidates.first)
        XCTAssertEqual(candidate.kind, .nameConflict)
        model.updateConflictStrategy(for: candidate.id, strategy: .keepBoth)
        try await waitForSucceededPhase(model)

        let resolvedImports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(resolvedImports.map(\.duplicateStrategy), [.skip, .keepBoth])
        XCTAssertEqual(resolvedImports.last?.filename, "Plan (2).pdf")
        XCTAssertEqual(model.phase, .succeeded)
    }

    func testReplaceRequiresCorePlanAndSecondConfirmationBeforeApply() async throws {
        let source = try makeSelectedFile(name: "Plan.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(
            prediction: .fixture(category: "docs"),
            importErrors: [.nameConflict("docs/Plan.pdf")],
            replacePlan: .fixture(oldPath: "docs/Plan.pdf", newPath: "docs/Plan.pdf")
        )
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider(),
            allowReplaceDuringImport: true
        )

        await model.prepare()
        await model.importFiles()

        let candidate = try XCTUnwrap(model.replaceCandidates.first)
        model.updateConflictStrategy(for: candidate.id, strategy: .replace)
        let confirmation = try await waitForPendingReplace(model)
        model.confirmReplace(confirmation, understandsReplace: false)
        XCTAssertEqual(model.replaceErrorMessage, "Confirm that you understand this will replace the existing file.")

        model.confirmReplace(confirmation, understandsReplace: true)
        try await waitForSucceededPhase(model)

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip])
        let planRequests = await bridge.replacePlanRequestsSnapshot()
        XCTAssertEqual(planRequests.map(\.existingPath), ["docs/Plan.pdf"])
        let replaceRequests = await bridge.replaceRequestsSnapshot()
        XCTAssertEqual(replaceRequests.map(\.plan.affectedFileID), [42])
        XCTAssertNil(model.pendingReplaceConfirmation)
        XCTAssertTrue(model.replaceCandidates.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testReplaceCannotBeConfirmedWhenCorePreflightBlocksTrash() async throws {
        let source = try makeSelectedFile(name: "Existing.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(
            prediction: .fixture(category: "docs"),
            importErrors: [.duplicateContent("docs/Existing.pdf")],
            replacePlan: .fixtureBlocked(oldPath: "docs/Existing.pdf", reason: "Replace requires system Trash.")
        )
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider(),
            allowReplaceDuringImport: true
        )

        await model.prepare()
        await model.importFiles()

        let candidate = try XCTUnwrap(model.replaceCandidates.first)
        model.updateConflictStrategy(for: candidate.id, strategy: .replace)
        try await waitForReplaceError(model, "Replace requires system Trash.")

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip])
        let replaceRequests = await bridge.replaceRequestsSnapshot()
        XCTAssertTrue(replaceRequests.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testReplaceDisabledByRepositoryConfigDoesNotRunCorePreflight() async throws {
        let source = try makeSelectedFile(name: "Existing.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(
            prediction: .fixture(category: "docs"),
            importErrors: [.nameConflict("docs/Existing.pdf")]
        )
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider(),
            allowReplaceDuringImport: false
        )

        await model.prepare()
        await model.importFiles()

        let candidate = try XCTUnwrap(model.replaceCandidates.first)
        model.updateConflictStrategy(for: candidate.id, strategy: .replace)
        try await Task.sleep(nanoseconds: 50_000_000)

        let planRequests = await bridge.replacePlanRequestsSnapshot()
        let replaceRequests = await bridge.replaceRequestsSnapshot()
        XCTAssertEqual(model.replaceUnavailableReason, "Replace is disabled in repository settings.")
        XCTAssertTrue(planRequests.isEmpty)
        XCTAssertTrue(replaceRequests.isEmpty)
        XCTAssertNil(model.pendingReplaceConfirmation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testICloudPlaceholderFailureStaysRecoverableAndKeepsSource() async throws {
        let source = try makeSelectedFile(name: "Cloud.pdf")
        defer { removeSelectedFile(source) }
        let bridge = FakeFilesImportCoreBridge(
            prediction: .fixture(category: "docs"),
            importErrors: [.iCloudPlaceholder(source.path)]
        )
        let model = FilesImportReviewModel(
            repoPath: "/tmp/Repo",
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )

        await model.prepare()
        await model.importFiles()

        XCTAssertEqual(model.error, .iCloudPlaceholder(source.path))
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testLiveCoreImportFileWritesSelectionAndListFilesShowsIt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("Repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let source = try makeSelectedFile(name: "FilesEvidence.txt")
        defer { removeSelectedFile(source) }
        let bridge = LiveMobileRepositoryCoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repo.path)

        let model = FilesImportReviewModel(
            repoPath: repo.path,
            selectedURLs: [source],
            bridge: bridge,
            accessProvider: FakeFilesImportAccessProvider()
        )
        await model.prepare()
        model.filename = "Files Evidence.txt"
        model.updateCategory("inbox")
        await model.importFiles()

        XCTAssertEqual(model.phase, .succeeded)
        let importedFile = try XCTUnwrap(model.importedFiles.first)
        let files = try await bridge.listFiles(repoPath: repo.path, filter: .page(category: nil))
        XCTAssertTrue(files.contains { $0.id == importedFile.id && $0.currentName == "Files Evidence.txt" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent(importedFile.path).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeSelectedFile(name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixFilesImportSelection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("files import bytes".utf8).write(to: url)
        return url
    }

    private func removeSelectedFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixFilesImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForSucceededPhase(_ model: FilesImportReviewModel) async throws {
        for _ in 0 ..< 20 {
            if model.phase == .succeeded {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Expected Files import to reach succeeded phase.")
    }

    private func waitForPendingReplace(_ model: FilesImportReviewModel) async throws
        -> FilesImportReplaceConfirmation {
        for _ in 0 ..< 20 {
            if let confirmation = model.pendingReplaceConfirmation {
                return confirmation
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(model.pendingReplaceConfirmation)
    }

    private func waitForReplaceError(_ model: FilesImportReviewModel, _ expected: String) async throws {
        for _ in 0 ..< 20 {
            if model.replaceErrorMessage == expected {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(model.replaceErrorMessage, expected)
    }
}

private struct FakeFilesImportAccessProvider: FilesImportSecurityScopedAccessing {
    func beginAccessing(_ url: URL) throws -> FilesImportScopedAccess {
        FilesImportScopedAccess {}
    }
}

actor FakeFilesImportCoreBridge: FilesImportCoreBridge {
    typealias PredictionRequest = (repoPath: String, filename: String)

    private let prediction: FilesImportCategoryPrediction
    private var importErrors: [FilesImportError]
    private var replacePlan: FilesImportReplacePlan
    private var predictionRequests: [PredictionRequest] = []
    private var importRequests: [FilesImportCoreRequest] = []
    private var replacePlanRequests: [FilesImportReplacePlanRequest] = []
    private var replaceRequests: [FilesImportReplaceRequest] = []

    init(
        prediction: FilesImportCategoryPrediction,
        importErrors: [FilesImportError] = [],
        replacePlan: FilesImportReplacePlan = .fixture(oldPath: "docs/Existing.pdf", newPath: "docs/Existing.pdf")
    ) {
        self.prediction = prediction
        self.importErrors = importErrors
        self.replacePlan = replacePlan
    }

    func predictCategory(repoPath: String, filename: String) async throws -> FilesImportCategoryPrediction {
        predictionRequests.append((repoPath, filename))
        return prediction
    }

    func importSelectedFile(request: FilesImportCoreRequest) async throws -> MobileLibraryFile {
        importRequests.append(request)
        if !importErrors.isEmpty {
            throw importErrors.removeFirst()
        }
        return .fixture(id: Int64(importRequests.count), name: request.filename, category: request.category)
    }

    func prepareReplace(request: FilesImportReplacePlanRequest) async throws -> FilesImportReplacePlan {
        replacePlanRequests.append(request)
        return replacePlan
    }

    func replaceSelectedFile(request: FilesImportReplaceRequest) async throws -> FilesImportReplaceExecutionReport {
        replaceRequests.append(request)
        return .fixture(plan: request.plan, importedName: request.filename, category: request.category)
    }

    func predictionRequestsSnapshot() -> [PredictionRequest] {
        predictionRequests
    }

    func importRequestsSnapshot() -> [FilesImportCoreRequest] {
        importRequests
    }

    func replacePlanRequestsSnapshot() -> [FilesImportReplacePlanRequest] {
        replacePlanRequests
    }

    func replaceRequestsSnapshot() -> [FilesImportReplaceRequest] {
        replaceRequests
    }
}

private extension FilesImportCategoryPrediction {
    static func fixture(category: String) -> FilesImportCategoryPrediction {
        FilesImportCategoryPrediction(category: category, suggestedName: "", confidence: 0.9)
    }
}

private extension FilesImportReplacePlan {
    static func fixture(oldPath: String, newPath: String) -> FilesImportReplacePlan {
        FilesImportReplacePlan(
            confirmationID: "token-replace",
            oldPath: oldPath,
            newPath: newPath,
            oldHashSHA256: "old-hash",
            newHashSHA256: "new-hash",
            affectedFileID: 42,
            backupTarget: "System Trash through Core batch_delete_to_trash.",
            databaseUpdate: "Soft-delete record 42, then import \(newPath).",
            changeLogAction: "deleted + imported",
            recoveryNote: "Restore from Core undo token or system Trash.",
            trashAvailable: true,
            undoAvailable: true,
            canReplace: true,
            blockedReason: nil,
            previewToken: "token-replace"
        )
    }

    static func fixtureBlocked(oldPath: String, reason: String) -> FilesImportReplacePlan {
        var plan = fixture(oldPath: oldPath, newPath: oldPath)
        plan.trashAvailable = false
        plan.undoAvailable = false
        plan.canReplace = false
        plan.blockedReason = reason
        plan.backupTarget = "Unavailable"
        plan.recoveryNote = reason
        return plan
    }
}

private extension FilesImportReplaceExecutionReport {
    static func fixture(
        plan: FilesImportReplacePlan,
        importedName: String,
        category: String
    ) -> FilesImportReplaceExecutionReport {
        FilesImportReplaceExecutionReport(
            importedFile: .fixture(id: 2, name: importedName, category: category),
            oldFileID: plan.affectedFileID,
            oldPath: plan.oldPath,
            newPath: plan.newPath,
            oldHashSHA256: plan.oldHashSHA256,
            newHashSHA256: plan.newHashSHA256,
            backupTarget: plan.backupTarget,
            databaseUpdate: plan.databaseUpdate,
            changeLogAction: plan.changeLogAction,
            recoveryNote: plan.recoveryNote,
            undoToken: "undo-replace-42",
            affectedFileIDs: [plan.affectedFileID, 2]
        )
    }
}

private extension MobileLibraryFile {
    static func fixture(id: Int64, name: String, category: String) -> MobileLibraryFile {
        MobileLibraryFile(
            id: id,
            path: "\(category)/\(name)",
            originalName: name,
            currentName: name,
            category: category,
            sizeBytes: 20,
            hashSha256: "hash-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            availability: .available,
            importedAt: 1,
            updatedAt: 1
        )
    }
}
