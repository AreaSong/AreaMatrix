@testable import AreaMatrix
import XCTest

final class ImportDropPreviewModelTests: XCTestCase {
    @MainActor
    func testAutoClassifyHoverCallsInjectedCoreCategoryPredictor() async {
        let sourceURL = importBatchInvoiceURL()
        let predictor = ImportDropRecordingPredictor(result: importDropInvoicePrediction())
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [sourceURL])
        await predictor.assertCategoryPredictionRequests([
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf")
        ])
        XCTAssertEqual(model.presentation?.destinationLabel, "finance")
        XCTAssertEqual(model.presentation?.predictionLabel, "Classification preview: finance · keyword · 90%")
        XCTAssertEqual(model.presentation?.headline, "Drop files to import")
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    func testDefaultCoreBridgePredictsCategoryFromInitializedRepository() async throws {
        let repoURL = try makeImportDropTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }
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
        let sourceURL = importBatchInvoiceURL()
        let predictor = ImportDropRecordingPredictor(result: importDropInvoicePrediction())
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .category("docs"), urls: [sourceURL])

        await predictor.assertCategoryPredictionRequests([])
        XCTAssertEqual(model.presentation?.destinationLabel, "docs")
        XCTAssertNil(model.presentation?.prediction)
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    @MainActor
    func testClassifyErrorsMapToHoverWarningWithoutCreatingStaticSuccess() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/bad.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .failure(CoreError.Config(reason: "classifier.yaml line 7"))
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [sourceURL])

        XCTAssertEqual(model.presentation?.warning, L10n.display(
            "Cannot preview category",
            technicalDetail: "classifier.yaml line 7"
        ))
        XCTAssertNil(model.presentation?.prediction)
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    @MainActor
    func testInvalidItemsShowAccessibleWarningAndSkipPredictor() async throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/file.pdf"))
        let predictor = ImportDropRecordingPredictor(results: [])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [remoteURL])

        await predictor.assertCategoryPredictionRequests([])
        XCTAssertEqual(model.presentation?.warning, L10n.display("Cannot import this item"))
        XCTAssertEqual(model.presentation?.destinationLabel, "Auto classify")
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    func testSidebarRowsExposeDragHoverDropTargets() {
        let root = RepositorySidebarRowSnapshot.testFixture()
        let finance = RepositorySidebarRowSnapshot.testFixture(node: .testCategory("finance", fileCount: 2))
        let contracts = RepositorySidebarRowSnapshot.testFixture(
            node: .testSubdirectory("contracts", relativePath: "finance/contracts", fileCount: 1),
            depth: 1
        )

        XCTAssertEqual(root.importDropTarget, .repositoryRoot)
        XCTAssertEqual(finance.importDropTarget, .category("finance"))
        XCTAssertEqual(contracts.importDropTarget, .category("finance"))
        XCTAssertEqual(finance.importDropTarget.sidebarHelp, "Import into \"finance\"")
    }
}

private func importDropInvoicePrediction() -> ClassifyResultSnapshot {
    .importSingleFileFixture(
        category: "finance",
        suggestedName: "Invoice_2026Q1.pdf",
        reason: .keyword,
        confidence: 0.9
    )
}
