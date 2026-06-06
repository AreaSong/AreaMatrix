@testable import AreaMatrixIOS
import Foundation
import XCTest

@MainActor
final class CameraImportReviewModelTests: XCTestCase {
    func testPrepareUsesCorePredictionForDefaultCategory() async throws {
        let source = try makeCapturedPhoto()
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeCameraImportCoreBridge(prediction: .fixture(category: "receipts"))
        let model = CameraImportReviewModel(repoPath: "/tmp/Repo", sourceURL: source, bridge: bridge)

        await model.prepare()

        let predictions = await bridge.predictionRequestsSnapshot()
        XCTAssertEqual(predictions.map(\.filename), [model.filename])
        XCTAssertEqual(model.category, "receipts")
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.canImport)
    }

    func testUnreadablePhotoDoesNotCallCoreImport() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-\(UUID()).jpg")
        let bridge = FakeCameraImportCoreBridge(prediction: .fixture(category: "receipts"))
        let model = CameraImportReviewModel(repoPath: "/tmp/Repo", sourceURL: source, bridge: bridge)

        await model.prepare()

        let predictions = await bridge.predictionRequestsSnapshot()
        XCTAssertTrue(predictions.isEmpty)
        XCTAssertEqual(model.error, .unreadableSource(source.path))
        XCTAssertEqual(model.phase, .failed)
    }

    func testImportUsesCopiedCategoryRequestThroughCoreBridge() async throws {
        let source = try makeCapturedPhoto()
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeCameraImportCoreBridge(prediction: .fixture(category: "receipts"))
        let model = CameraImportReviewModel(repoPath: "/tmp/Repo", sourceURL: source, bridge: bridge)

        await model.prepare()
        await model.importPhoto()

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports.first?.repoPath, "/tmp/Repo")
        XCTAssertEqual(imports.first?.sourceURL, source)
        XCTAssertEqual(imports.first?.category, "receipts")
        XCTAssertEqual(imports.first?.duplicateStrategy, .skip)
        XCTAssertEqual(model.importedFile?.currentName, model.filename)
        XCTAssertEqual(model.phase, .succeeded)
    }

    func testDuplicateContentStaysInSheetAndKeepBothRetries() async throws {
        let source = try makeCapturedPhoto()
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeCameraImportCoreBridge(
            prediction: .fixture(category: "receipts"),
            importErrors: [.duplicateContent("receipts/existing.jpg")]
        )
        let model = CameraImportReviewModel(repoPath: "/tmp/Repo", sourceURL: source, bridge: bridge)

        await model.prepare()
        await model.importPhoto()
        XCTAssertEqual(model.conflict, .duplicateContent(existingPath: "receipts/existing.jpg"))
        XCTAssertEqual(model.phase, .ready)

        await model.keepDuplicateAndRetry()

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip, .keepBoth])
        XCTAssertEqual(model.phase, .succeeded)
    }

    func testNameConflictShowsKeepBothFilenameAndRetries() async throws {
        let source = try makeCapturedPhoto()
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeCameraImportCoreBridge(
            prediction: .fixture(category: "inbox"),
            importErrors: [.nameConflict("inbox/Photo 2026-04-29 1130.jpg")]
        )
        let model = CameraImportReviewModel(repoPath: "/tmp/Repo", sourceURL: source, bridge: bridge)
        model.filename = "Photo 2026-04-29 1130.jpg"

        await model.prepare()
        await model.importPhoto()

        XCTAssertEqual(
            model.conflict,
            .nameConflict(
                existingPath: "inbox/Photo 2026-04-29 1130.jpg",
                resolvedFilename: "Photo 2026-04-29 1130 (2).jpg"
            )
        )
        XCTAssertEqual(model.filename, "Photo 2026-04-29 1130 (2).jpg")
        XCTAssertEqual(model.phase, .ready)

        await model.keepConflictAndRetry()

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip, .keepBoth])
        XCTAssertEqual(imports.last?.filename, "Photo 2026-04-29 1130 (2).jpg")
        XCTAssertEqual(model.phase, .succeeded)
    }

    func testLiveCoreImportFileWritesPhotoAndListFilesShowsIt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("Repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let source = try makeCapturedPhoto(name: "CameraEvidence.jpg")
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = LiveMobileRepositoryCoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repo.path)
        let model = CameraImportReviewModel(repoPath: repo.path, sourceURL: source, bridge: bridge)
        await model.prepare()
        model.filename = "Camera Evidence.jpg"
        model.updateCategory("inbox")
        await model.importPhoto()

        XCTAssertEqual(model.phase, .succeeded)
        let importedFile = try XCTUnwrap(model.importedFile)
        let files = try await bridge.listFiles(repoPath: repo.path, filter: .page(category: nil))
        XCTAssertTrue(files.contains { $0.id == importedFile.id && $0.currentName == "Camera Evidence.jpg" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent(importedFile.path).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testDiscardOnlyRemovesAreaMatrixOwnedTemporaryPhoto() throws {
        let owned = SystemCapturedPhotoStore.temporaryURL()
        let unrelated = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserPhoto-\(UUID().uuidString).jpg")
        try Data("owned".utf8).write(to: owned)
        try Data("unrelated".utf8).write(to: unrelated)
        defer { try? FileManager.default.removeItem(at: unrelated) }

        SystemCapturedPhotoStore.discardIfOwned(owned)
        SystemCapturedPhotoStore.discardIfOwned(unrelated)

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func makeCapturedPhoto(name: String? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name ?? "Captured-\(UUID().uuidString).jpg")
        try Data("jpeg bytes".utf8).write(to: url)
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixCameraImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

actor FakeCameraImportCoreBridge: CameraImportCoreBridge {
    typealias PredictionRequest = (repoPath: String, filename: String)

    private let prediction: CameraImportCategoryPrediction
    private var importErrors: [CameraImportError]
    private var predictionRequests: [PredictionRequest] = []
    private var importRequests: [CameraImportCoreRequest] = []

    init(
        prediction: CameraImportCategoryPrediction,
        importErrors: [CameraImportError] = []
    ) {
        self.prediction = prediction
        self.importErrors = importErrors
    }

    func predictCategory(repoPath: String, filename: String) async throws -> CameraImportCategoryPrediction {
        predictionRequests.append((repoPath, filename))
        return prediction
    }

    func importCapturedPhoto(request: CameraImportCoreRequest) async throws -> MobileLibraryFile {
        importRequests.append(request)
        if !importErrors.isEmpty {
            throw importErrors.removeFirst()
        }
        return .fixture(id: Int64(importRequests.count), name: request.filename, category: request.category)
    }

    func predictionRequestsSnapshot() -> [PredictionRequest] {
        predictionRequests
    }

    func importRequestsSnapshot() -> [CameraImportCoreRequest] {
        importRequests
    }
}

private extension CameraImportCategoryPrediction {
    static func fixture(category: String) -> CameraImportCategoryPrediction {
        CameraImportCategoryPrediction(category: category, suggestedName: "", confidence: 0.9)
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
            sizeBytes: 10,
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
