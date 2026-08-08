@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreAICallLogContractTests: XCTestCase {
    func testAICallLogCapabilityProtocolsCanBeImplementedWithoutGeneratedBindings() async throws {
        let implementation = ContractDouble()
        let page = try await implementation.listAICalls(
            repoPath: "/tmp/repo",
            filter: AICallLogFilterSnapshot(
                feature: .classification,
                route: .local,
                status: .success,
                occurredAfter: 1,
                occurredBefore: 2,
                searchQuery: "report"
            ),
            pagination: AICallLogPaginationSnapshot(limit: 20, offset: 0)
        )
        let report = try await implementation.clearAICallLog(
            repoPath: "/tmp/repo",
            request: AICallLogClearRequestSnapshot(scope: .selectedEntries, entryIds: [7], olderThan: nil)
        )

        XCTAssertEqual(page.records.map(\.id), [7])
        XCTAssertEqual(page.records.first?.route, .local)
        XCTAssertEqual(report.deletedCount, 1)
    }

    func testAICallLogSnapshotsPreserveStableFilterAndPrivacyFields() {
        let record = AICallLogRecordSnapshot(
            id: 11,
            occurredAt: 100,
            feature: .summary,
            fileId: 12,
            fileDisplayName: "report.md",
            batchId: "batch-1",
            scope: "selected",
            route: .remote,
            providerName: "provider",
            modelName: "model",
            status: .skipped,
            durationMs: nil,
            sentFields: [.fileName, .extractedTextExcerpt],
            privacyRulesChecked: true,
            privacyRuleId: "rule-1",
            privacyRuleName: "Private",
            matchedFieldType: .extractedTextExcerpt,
            resultSummary: "blocked",
            errorCode: "privacy_rule"
        )

        XCTAssertEqual(record.sentFields, [.fileName, .extractedTextExcerpt])
        XCTAssertEqual(record.matchedFieldType, .extractedTextExcerpt)
        XCTAssertTrue(record.privacyRulesChecked)
        XCTAssertEqual(record.errorCode, "privacy_rule")
    }
}

private struct ContractDouble: CoreAICallLogListing, CoreAICallLogClearing {
    func listAICalls(
        repoPath _: String,
        filter _: AICallLogFilterSnapshot,
        pagination _: AICallLogPaginationSnapshot
    ) async throws -> AICallLogPageSnapshot {
        AICallLogPageSnapshot(
            totalCount: 1,
            records: [
                AICallLogRecordSnapshot(
                    id: 7,
                    occurredAt: 1,
                    feature: .classification,
                    fileId: nil,
                    fileDisplayName: nil,
                    batchId: nil,
                    scope: nil,
                    route: .local,
                    providerName: nil,
                    modelName: nil,
                    status: .success,
                    durationMs: 1,
                    sentFields: [],
                    privacyRulesChecked: true,
                    privacyRuleId: nil,
                    privacyRuleName: nil,
                    matchedFieldType: nil,
                    resultSummary: "ok",
                    errorCode: nil
                )
            ],
            limit: 20,
            offset: 0,
            hasMore: false,
            retentionDays: 30,
            redactionPolicy: "safe"
        )
    }

    func clearAICallLog(
        repoPath _: String,
        request _: AICallLogClearRequestSnapshot
    ) async throws -> AICallLogClearReportSnapshot {
        AICallLogClearReportSnapshot(deletedCount: 1, remainingCount: 0, clearedAt: 2)
    }
}
