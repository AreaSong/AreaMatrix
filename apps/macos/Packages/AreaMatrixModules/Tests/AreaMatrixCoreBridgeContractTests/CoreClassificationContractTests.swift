@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreClassificationContractTests: XCTestCase {
    func testClassificationReasonWireValuesAreStable() {
        XCTAssertEqual(ClassifyReasonSnapshot.keyword.rawValue, "Keyword")
        XCTAssertEqual(ClassifyReasonSnapshot.extension.rawValue, "Extension")
        XCTAssertEqual(ClassifyReasonSnapshot.aiPredicted.rawValue, "AiPredicted")
        XCTAssertEqual(ClassifyReasonSnapshot.default.rawValue, "Default")
    }

    func testClassificationResultPreservesStableValues() {
        let result = ClassifyResultSnapshot(
            category: "Work",
            suggestedName: "meeting-notes.md",
            reason: .aiPredicted,
            confidence: 0.92
        )

        XCTAssertEqual(result.category, "Work")
        XCTAssertEqual(result.suggestedName, "meeting-notes.md")
        XCTAssertEqual(result.reason, .aiPredicted)
        XCTAssertEqual(result.confidence, 0.92)
        XCTAssertEqual(result, result)
    }

    func testClassificationCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let predictor = ClassificationContractDouble()
        let result = try await predictor.predictCategory(repoPath: "/tmp/repository", filename: "meeting.md")

        XCTAssertEqual(result.category, "Work")
        XCTAssertEqual(result.reason, .keyword)
    }
}

private struct ClassificationContractDouble: CoreCategoryPredicting {
    func predictCategory(repoPath _: String, filename _: String) async throws -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: "Work",
            suggestedName: "meeting.md",
            reason: .keyword,
            confidence: 0.8
        )
    }
}
