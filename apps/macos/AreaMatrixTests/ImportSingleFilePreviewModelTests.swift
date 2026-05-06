import XCTest
@testable import AreaMatrix

final class ImportSingleFilePreviewModelTests: XCTestCase {
    @MainActor
    func testSingleFileSheetCallsCorePredictorAndPrefillsVisibleFields() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同_客户A.pdf",
                reason: .keyword,
                confidence: 0.93
            )),
        ])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        )
        let model = ImportSingleFilePreviewModel(predictor: predictor)

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFilePredictRequest(repoPath: "/tmp/repo", filename: "合同.pdf"),
        ])
        XCTAssertEqual(model.source?.fileName, "合同.pdf")
        XCTAssertEqual(model.selectedCategory, "docs")
        XCTAssertEqual(model.suggestedName, "2026Q1_合同_客户A.pdf")
        XCTAssertEqual(model.reasonSummary, "keyword · 93%")
        XCTAssertEqual(model.status, .ready)
    }

    @MainActor
    func testExplicitCategoryKeepsUserSelectedDestinationWhileStillPreviewingName() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同_客户A.pdf",
                reason: .extension,
                confidence: 0.8
            )),
        ])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .category("finance"),
            urls: [URL(fileURLWithPath: "/tmp/合同.pdf")],
            kind: .singleFile
        )
        let model = ImportSingleFilePreviewModel(predictor: predictor)

        await model.load(request: request)

        XCTAssertEqual(model.selectedCategory, "finance")
        XCTAssertEqual(model.prediction?.category, "docs")
        XCTAssertEqual(model.suggestedName, "2026Q1_合同_客户A.pdf")
        XCTAssertEqual(model.status, .ready)
    }

    @MainActor
    func testClassificationFailureDoesNotCreateStaticPreviewSuccess() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .failure(CoreError.Classify(reason: "classifier unavailable")),
        ])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )
        let model = ImportSingleFilePreviewModel(predictor: predictor)

        await model.load(request: request)

        XCTAssertNil(model.prediction)
        XCTAssertEqual(model.selectedCategory, "inbox")
        XCTAssertEqual(model.suggestedName, "source.pdf")
        XCTAssertEqual(model.status, .failed("无法预览分类：classifier unavailable"))
    }

    @MainActor
    func testNonSingleFileRequestSkipsC105Predictor() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [
                URL(fileURLWithPath: "/tmp/a.pdf"),
                URL(fileURLWithPath: "/tmp/b.pdf"),
            ],
            kind: .multipleItems(2)
        )
        let model = ImportSingleFilePreviewModel(predictor: predictor)

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertNil(model.prediction)
        XCTAssertEqual(model.status, .unsupported("此 sheet 只处理单文件导入"))
    }
}

private struct ImportSingleFilePredictRequest: Equatable, Sendable {
    var repoPath: String
    var filename: String
}

private actor ImportSingleFileRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportSingleFilePredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportSingleFilePredictRequest(repoPath: repoPath, filename: filename))
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

    func recordedRequests() -> [ImportSingleFilePredictRequest] {
        requests
    }
}
