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
        XCTAssertEqual(imports.map(\.duplicateStrategy), [.skip, .keepBoth])
        XCTAssertEqual(imports.last?.filename, "Plan (2).pdf")
        XCTAssertEqual(model.phase, .succeeded)
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
    private var predictionRequests: [PredictionRequest] = []
    private var importRequests: [FilesImportCoreRequest] = []

    init(
        prediction: FilesImportCategoryPrediction,
        importErrors: [FilesImportError] = []
    ) {
        self.prediction = prediction
        self.importErrors = importErrors
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

    func predictionRequestsSnapshot() -> [PredictionRequest] {
        predictionRequests
    }

    func importRequestsSnapshot() -> [FilesImportCoreRequest] {
        importRequests
    }
}

private extension FilesImportCategoryPrediction {
    static func fixture(category: String) -> FilesImportCategoryPrediction {
        FilesImportCategoryPrediction(category: category, suggestedName: "", confidence: 0.9)
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
