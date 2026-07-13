@testable import AreaMatrix
import XCTest

actor StaticCoreErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func assertMappedCoreErrors(
        _ expectedErrors: [CoreError],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(errors, expectedErrors, file: file, line: line)
    }

    func assertMappedCoreErrorCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(errors.count, expectedCount, file: file, line: line)
    }

    func assertFirstMappedInternalErrorContains(
        _ expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .Internal(message)? = errors.first else {
            return XCTFail("expected first recorded error to be CoreError.Internal", file: file, line: line)
        }
        XCTAssertTrue(message.contains(expectedMessage), file: file, line: line)
    }
}

actor RecordingCoreErrorMapper: CoreErrorMapping {
    private let mapping: @Sendable (CoreError) -> CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: @escaping @Sendable (CoreError) -> CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping(error)
    }

    func assertMappedCoreErrors(
        _ expectedErrors: [CoreError],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(errors, expectedErrors, file: file, line: line)
    }

    func assertMappedCoreErrorCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(errors.count, expectedCount, file: file, line: line)
    }
}

extension CoreErrorMappingSnapshot {
    static func testFixture(
        kind: CoreErrorKindSnapshot,
        userMessage: String,
        severity: CoreErrorSeveritySnapshot = .medium,
        suggestedAction: String = "Retry",
        recoverability: CoreErrorRecoverabilitySnapshot = .retryable,
        rawContext: String? = nil
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: severity,
            suggestedAction: suggestedAction,
            recoverability: recoverability,
            rawContext: rawContext ?? kind.rawValue
        )
    }
}

extension RecordingCoreErrorMapper {
    static func aiPrivacyRulesSettingsConfig() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: .io,
                userMessage: String(describing: error),
                suggestedAction: "Retry save",
                rawContext: "ai-privacy-rules ai-settings-config"
            )
        }
    }

    static func batchChangeCategory() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: CoreErrorKindTestMapper.kind(for: error),
                userMessage: "Batch category update failed",
                suggestedAction: "Review failed items and refresh the preview.",
                recoverability: .refreshRequired,
                rawContext: "batch-change-category batch-change-category-core batch-change-category"
            )
        }
    }

    static func undoToast() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: CoreErrorKindTestMapper.kind(for: error),
                userMessage: "Undo failed",
                suggestedAction: "View details in Undo history.",
                recoverability: .refreshRequired,
                rawContext: "undo-toast undo-action-log undo-action-log"
            )
        }
    }

    static func undoHistory() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: CoreErrorKindTestMapper.kind(for: error),
                userMessage: "Undo failed",
                suggestedAction: "View details in Undo history.",
                recoverability: .refreshRequired,
                rawContext: "undo-history undo-action-log undo-action-log"
            )
        }
    }
}
