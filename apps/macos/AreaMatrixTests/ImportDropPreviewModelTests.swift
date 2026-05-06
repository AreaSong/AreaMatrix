import XCTest
@testable import AreaMatrix

final class ImportDropPreviewModelTests: XCTestCase {
    @MainActor
    func testAutoClassifyHoverCallsInjectedCoreCategoryPredictor() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [sourceURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf"),
        ])
        XCTAssertEqual(model.presentation?.destinationLabel, "finance")
        XCTAssertEqual(model.presentation?.predictionLabel, "Classification preview: finance · keyword · 90%")
        XCTAssertEqual(model.presentation?.headline, "Drop files to import")
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    func testDefaultCoreBridgePredictsCategoryFromInitializedRepository() async throws {
        let repoURL = try makeImportDropTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let result = try await bridge.predictCategory(
            repoPath: repoURL.path,
            filename: "Invoice_2026Q1.pdf"
        )

        XCTAssertEqual(result.category, "finance")
        XCTAssertEqual(result.reason, .keyword)
        XCTAssertGreaterThan(result.confidence, 0)
    }

    @MainActor
    func testExplicitSidebarCategoryDoesNotRunAutoClassifyPreview() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .category("docs"), urls: [sourceURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.presentation?.destinationLabel, "docs")
        XCTAssertNil(model.presentation?.prediction)
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    @MainActor
    func testClassifyErrorsMapToHoverWarningWithoutCreatingStaticSuccess() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/bad.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .failure(CoreError.Config(reason: "classifier.yaml line 7")),
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [sourceURL])

        XCTAssertEqual(model.presentation?.warning, "Classifier settings are invalid: classifier.yaml line 7")
        XCTAssertNil(model.presentation?.prediction)
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    @MainActor
    func testInvalidItemsShowAccessibleWarningAndSkipPredictor() async throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/file.pdf"))
        let predictor = ImportDropRecordingPredictor(results: [])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [remoteURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.presentation?.warning, "Cannot import this item")
        XCTAssertEqual(model.presentation?.destinationLabel, "Auto classify")
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    func testSidebarRowsExposeS116DropTargets() {
        let root = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: []
        ), depth: 0)
        let finance = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
            slug: "finance",
            displayName: "finance",
            fileCount: 2,
            children: []
        ), depth: 0)
        let contracts = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
            slug: "contracts",
            displayName: "contracts",
            kind: "Subdir",
            relativePath: "finance/contracts",
            fileCount: 1,
            depth: 2,
            children: []
        ), depth: 1)

        XCTAssertEqual(root.importDropTarget, .repositoryRoot)
        XCTAssertEqual(finance.importDropTarget, .category("finance"))
        XCTAssertEqual(contracts.importDropTarget, .category("finance"))
        XCTAssertEqual(finance.importDropTarget.sidebarHelp, "Import into \"finance\"")
    }
}

private struct ImportDropPredictRequest: Equatable, Sendable {
    var repoPath: String
    var filename: String
}

private actor ImportDropRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportDropPredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportDropPredictRequest(repoPath: repoPath, filename: filename))
        guard !results.isEmpty else {
            throw CoreError.Classify(reason: "missing test result")
        }
        switch results.removeFirst() {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [ImportDropPredictRequest] {
        requests
    }
}

private func makeImportDropTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportDropTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
