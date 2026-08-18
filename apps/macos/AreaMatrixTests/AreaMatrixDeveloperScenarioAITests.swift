@testable import AreaMatrix
import AreaMatrixFeatureAI
import XCTest

final class AreaMatrixDeveloperScenarioAITests: XCTestCase {
    @MainActor
    func testAIScenarioFixturesAreDeterministicAndInMemory() async throws {
        let settings = DeveloperAISettingsStore()
        let provider = DeveloperRemoteProviderFixture()
        let privacy = DeveloperAIPrivacyFixture()
        let callLog = DeveloperAICallLogFixture()
        let localModel = DeveloperLocalModelFixture()
        let summary = DeveloperAISummaryFixture()

        let settingsSnapshot = try await settings.loadAISettings(repoPath: DeveloperAIScenarioFixture.repoPath)
        let providerSnapshot = try await provider.loadRemoteProviderConfig(
            repoPath: DeveloperAIScenarioFixture.repoPath
        )
        let privacySnapshot = try await privacy.loadAIPrivacyRules(repoPath: DeveloperAIScenarioFixture.repoPath)
        let callLogPage = try await callLog.listAICalls(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            filter: AICallLogFilterSnapshot(
                feature: nil,
                route: nil,
                status: nil,
                occurredAfter: nil,
                occurredBefore: nil,
                searchQuery: nil
            ),
            pagination: AICallLogPaginationSnapshot(limit: 100, offset: 0)
        )
        let localSnapshot = try await localModel.getLocalModelStatus(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            request: LocalModelStatusRequestState(
                modelID: LocalModelStatusModel.defaultModelID,
                storageLocation: DeveloperAIScenarioFixture.localModelStatus.storageLocation,
                cachedStatus: nil
            )
        )
        let summarySnapshot = try await summary.loadAISummaryState(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            fileID: DeveloperAIScenarioFixture.fileID
        )

        XCTAssertTrue(settingsSnapshot.config.aiEnabled)
        XCTAssertTrue(providerSnapshot.providerVerified)
        XCTAssertTrue(privacySnapshot.privacyGateEnabled)
        XCTAssertEqual(callLogPage.records.count, 2)
        XCTAssertEqual(localSnapshot.availability, .ready)
        XCTAssertEqual(summarySnapshot.summary, DeveloperAIScenarioFixture.savedSummary)
        XCTAssertEqual(
            DeveloperRemoteCredentialStore().storedCredentialReference(provider: .openAi, endpointURL: nil),
            "developer-memory:openAi:managed"
        )
    }
}
