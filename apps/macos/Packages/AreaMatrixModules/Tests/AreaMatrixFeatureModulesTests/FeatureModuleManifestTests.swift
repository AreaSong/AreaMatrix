import AreaMatrixCoreContracts
import AreaMatrixFeatureAI
import AreaMatrixFeatureIngestion
import AreaMatrixFeatureLibrary
import AreaMatrixFeatureOperation
import AreaMatrixFeatureSettings
import Foundation
import XCTest

final class FeatureModuleManifestTests: XCTestCase {
    func testValidationPhaseStatePreservesFailurePayload() {
        enum Failure: Equatable { case invalidPath }

        let state = ValidationPhaseState<Failure>.failed(.invalidPath)

        XCTAssertEqual(state, .failed(.invalidPath))
        XCTAssertNotEqual(state, .validating)
    }

    func testLocalModelContractsPreserveBusyAndCachedState() {
        let status = LocalModelStatusState(
            modelID: "local-default",
            storageLocation: "/tmp/models",
            availability: .verifying,
            version: "1",
            sizeBytes: 42,
            lastError: nil,
            recommendedAction: .openDiagnostics,
            lastCheckedAt: 100,
            diagnosticsSummary: "verifying",
            featureStatuses: [
                LocalModelFeatureStatusState(
                    feature: .semanticSearch,
                    available: false,
                    unavailableReason: "verifying"
                )
            ]
        )

        XCTAssertTrue(status.availability.isBusy)
        XCTAssertEqual(status.cachedStatus.modelID, status.modelID)
        XCTAssertEqual(status.cachedStatus.recommendedAction, .openDiagnostics)
        XCTAssertEqual(status.featureStatuses.map(\.id), [AISettingsFeatureKind.semanticSearch.rawValue])
    }

    func testLocalModelCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let reader = LocalModelContractReader()
        let status = try await reader.getLocalModelStatus(
            repoPath: "/tmp/repo",
            request: LocalModelStatusRequestState(modelID: "local-default", storageLocation: "/tmp/models")
        )
        let location = try await reader.locateLocalModelFolder(
            repoPath: "/tmp/repo",
            request: LocalModelFolderRequestState(modelID: "local-default", storageLocation: "/tmp/models")
        )

        XCTAssertEqual(status.availability, .ready)
        XCTAssertEqual(location.folderPath, "/tmp/models")
    }

    func testFeatureGroupsOwnExpectedManifestsWithoutOverlap() {
        let groups = [
            LibraryFeatureManifests.all,
            IngestionFeatureManifests.all,
            OperationFeatureManifests.all,
            SettingsFeatureManifests.all,
            AIFeatureManifests.all
        ]
        let all = groups.flatMap { $0 }

        XCTAssertEqual(Set(LibraryFeatureManifests.all.map(\.id)), ["CommandPalette", "Detail", "MainList", "Search"])
        XCTAssertEqual(Set(IngestionFeatureManifests.all.map(\.id)), ["Import", "Onboarding", "RepositoryLifecycle"])
        XCTAssertEqual(Set(OperationFeatureManifests.all.map(\.id)), ["FileActions", "SyncConflicts"])
        XCTAssertEqual(Set(SettingsFeatureManifests.all.map(\.id)), ["Settings"])
        XCTAssertEqual(Set(AIFeatureManifests.all.map(\.id)), ["AI"])
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    func testFeatureGroupsExposeCompleteOwnershipMetadata() {
        let manifests = [
            LibraryFeatureManifests.all,
            IngestionFeatureManifests.all,
            OperationFeatureManifests.all,
            SettingsFeatureManifests.all,
            AIFeatureManifests.all
        ].flatMap { $0 }

        XCTAssertFalse(manifests.isEmpty)
        XCTAssertTrue(manifests.allSatisfy { !$0.owner.isEmpty && !$0.responsibility.isEmpty })
    }

    func testFeatureStateContractsRemainValueOnlyAndStable() {
        XCTAssertEqual(DetailPaneTab.allCases.map(\.id), ["meta", "summary", "log", "note"])
        XCTAssertEqual(MainDetailTabRequest.automatic(.log), .automatic(.log))
        XCTAssertEqual(MainFileSelectionState.single(42).singleFileID, 42)
        XCTAssertEqual(MainFileSelectionState.multiple([1, 2]).multipleFileIDs, [1, 2])
        XCTAssertEqual(
            ImportEntryKind.resolved(
                for: [URL(fileURLWithPath: "/tmp/folder")],
                isDirectory: { _ in true }
            ),
            .folder
        )
        XCTAssertEqual(ImportEntryDestination.category("docs"), .category("docs"))
        XCTAssertEqual(ImportBatchNamingStrategy.uniformPrefix.id, "uniformPrefix")
        XCTAssertEqual("Quarter:Plan?.pdf".importBatchNormalizedFilename, "Quarter-Plan-.pdf")
        XCTAssertEqual(BatchTagApplyNormalizationResult.success(["swift"]), .success(["swift"]))
        XCTAssertEqual(
            BatchTagPendingState(input: "swift", pendingTags: ["swift"], fieldError: nil).pendingTags,
            ["swift"]
        )
        XCTAssertEqual(
            RepoMetadataPresence(hasMetadataDirectory: true, hasMetadataDatabase: false),
            RepoMetadataPresence(hasMetadataDirectory: true, hasMetadataDatabase: false)
        )
        XCTAssertEqual(AICallLogDateRangePreset.last30Days, .last30Days)
        XCTAssertEqual(RemoteProviderTestStatusState.connectionFailed, .connectionFailed)
        XCTAssertEqual(SemanticSearchResultGroup.semantic, .semantic)
        XCTAssertEqual(MainRepositoryContentState.empty, .empty)
        XCTAssertEqual(ImportProgressRecoveryPhase.retryBlocked("locked"), .retryBlocked("locked"))
        XCTAssertEqual(ImportProgressDiagnosticsPhase.collecting, .collecting)
        XCTAssertEqual(ImportProgressStopPhase.stopped, .stopped)
        XCTAssertEqual(RepositorySettingsDatabaseStatus.needsRecovery, .needsRecovery)
        XCTAssertEqual(RepositorySettingsWatcherStatus.paused, .paused)
        XCTAssertEqual(AIClassificationSuggestionStatusState.skipped, .skipped)
        XCTAssertEqual(AIClassificationSuggestionSkipReasonState.privacyRule, .privacyRule)
        XCTAssertEqual(
            AIClassificationSuggestionRequestState(
                fileID: 7,
                contextPolicy: .fileNameOnly,
                privacyPolicyRef: "block:private"
            ).privacyPolicyRef,
            "block:private"
        )
        XCTAssertEqual(
            RemoteProviderDisableRequestState(removeStoredCredential: true),
            RemoteProviderDisableRequestState(removeStoredCredential: true)
        )
    }

    @MainActor
    func testSidebarSelectionModelRetainsOrFallsBackWithinCurrentTree() {
        let model = MainSidebarSelectionModel(selectedID: "inbox")

        XCTAssertEqual(model.retainSelection(validIDs: ["inbox", "archive"], fallbackID: "archive"), "inbox")
        XCTAssertEqual(model.retainSelection(validIDs: ["archive"], fallbackID: "archive"), "archive")
        XCTAssertEqual(model.selectedID, "archive")
    }

    @MainActor
    func testLibrarySearchInputModelOwnsOnlyWindowLocalControls() {
        let model = MainRepositorySearchInputModel()

        XCTAssertEqual(model.filterText, "")
        XCTAssertEqual(model.searchScope, .all)
        XCTAssertEqual(model.searchMode, .normal)
        XCTAssertEqual(model.searchSort, .newestImported)
        XCTAssertEqual(model.searchFilters, .empty)

        model.filterText = "invoice"
        model.searchMode = .semantic
        XCTAssertEqual(model.filterText, "invoice")
        XCTAssertEqual(model.searchMode, .semantic)
    }

    func testBatchRenameContractsPreserveWireValues() {
        let rule = BatchRenameRuleSnapshot(
            mode: .keepBaseSequence,
            prefix: nil,
            dateSource: nil,
            dateFormat: nil,
            separator: "_",
            startNumber: 1,
            padding: 3,
            find: nil,
            replacement: nil,
            caseSensitive: false
        )
        XCTAssertEqual(rule.mode.id, "Keep base + sequence")
        XCTAssertEqual(rule.padding, 3)
        XCTAssertEqual(BatchRenamePreviewStatusSnapshot.externalChange.rawValue, "EXTERNAL_CHANGE")
        XCTAssertEqual(BatchRenameResultStatusSnapshot.displayNameUpdated.rawValue, "Display name updated")
    }

    func testAIClassificationSuggestionContractPreservesReviewState() {
        let suggestion = AIClassificationSuggestionState(
            fileID: 8,
            status: .suggested,
            currentCategory: "inbox",
            suggestedCategory: "finance",
            confidence: 0.9,
            reason: "invoice",
            route: .local,
            usedContext: [.fileName, .extension],
            skippedReason: nil,
            privacyRuleID: nil,
            callLogID: 11,
            requiresUserConfirmation: true
        )
        XCTAssertEqual(suggestion.suggestedCategory, "finance")
        XCTAssertEqual(suggestion.usedContext, [.fileName, .extension])
        XCTAssertTrue(suggestion.requiresUserConfirmation)
    }

    func testClassifierPreviewStateRejectsStaleResults() {
        var state = ClassifierSettingsPreviewState<String, String>()
        state.updateFilename("invoice.pdf")
        let firstGeneration = state.beginPreview()
        let currentGeneration = state.beginPreview()

        state.acceptResult("stale", generation: firstGeneration)
        state.acceptError("stale error", generation: firstGeneration)
        state.finishPreview(generation: firstGeneration)

        XCTAssertNil(state.result)
        XCTAssertNil(state.error)
        XCTAssertTrue(state.isPreviewing)

        state.acceptResult("finance", generation: currentGeneration)
        state.finishPreview(generation: currentGeneration)
        XCTAssertEqual(state.result, "finance")
        XCTAssertFalse(state.isPreviewing)
    }

    func testClassifierPreviewStateInvalidatesWorkWhenFilenameChangesOrClears() {
        var state = ClassifierSettingsPreviewState<String, String>()
        state.updateFilename("first.pdf")
        let generation = state.beginPreview()
        state.acceptError("failed", generation: generation)

        state.updateFilename("second.pdf")
        XCTAssertEqual(state.filename, "second.pdf")
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isPreviewing)
        XCTAssertFalse(state.isCurrentGeneration(generation))

        let nextGeneration = state.beginPreview()
        state.acceptResult("inbox", generation: nextGeneration)
        state.clear()
        XCTAssertNil(state.result)
        XCTAssertFalse(state.isPreviewing)
        XCTAssertFalse(state.isCurrentGeneration(nextGeneration))
    }

    func testRemoteProviderDraftNormalizesRequestsAndReportsTypedEnableBlockers() {
        var draft = RemoteProviderConfigDraft(
            provider: .other,
            modelID: "  custom-model  ",
            endpointURL: "  https://example.test/v1  ",
            apiKey: "  secret  ",
            selectedScopes: [],
            dataFlowConfirmed: false
        )

        XCTAssertTrue(draft.canTestConnection)
        XCTAssertEqual(draft.enableDisabledReason(verifiedToken: nil), .missingScope)
        XCTAssertEqual(
            draft.testRequest(keyReference: "key-ref"),
            RemoteProviderTestRequestState(
                provider: .other,
                modelID: "custom-model",
                endpointURL: "https://example.test/v1",
                keyReference: "key-ref"
            )
        )

        draft.selectedScopes = [.semanticSearch, .autoSummaries]
        XCTAssertEqual(draft.enableDisabledReason(verifiedToken: nil), .dataFlowUnconfirmed)
        draft.dataFlowConfirmed = true
        XCTAssertEqual(draft.enableDisabledReason(verifiedToken: nil), .connectionUnverified)

        let request = draft.enableRequest(token: "verified", keyReference: "key-ref")
        XCTAssertEqual(request.featureScope, [.autoSummaries, .semanticSearch])
        XCTAssertTrue(request.dataFlowConfirmed)
        XCTAssertTrue(draft.canEnable(verifiedToken: "verified"))
        XCTAssertNil(draft.enableDisabledReason(verifiedToken: "verified"))
        XCTAssertEqual(draft.fingerprint.apiKey, "secret")
    }

    func testRemoteProviderDraftRequiresAPIKeyAndIgnoresEndpointForBuiltInProvider() {
        var draft = RemoteProviderConfigDraft(
            provider: .openAi,
            modelID: "gpt-test",
            endpointURL: "https://ignored.example.test",
            apiKey: " ",
            selectedScopes: [.autoSummaries],
            dataFlowConfirmed: true
        )

        XCTAssertEqual(draft.enableDisabledReason(verifiedToken: nil), .missingAPIKey)
        XCTAssertFalse(draft.canTestConnection)
        draft.apiKey = "secret"
        XCTAssertNil(draft.testRequest(keyReference: "key-ref").endpointURL)
    }

    func testIngestionAndLibraryContractsPreserveFeatureState() {
        let identity = RepositoryIdentity(repoPath: "/tmp/example/../library")
        let access = RepositoryAccessSnapshot(isReadOnly: true, writeLockedFileIDs: [7])
        let context = RepositoryOperationContext(
            identity: identity,
            repoPath: "/tmp/library",
            expectedRevision: 9,
            access: access
        )
        XCTAssertEqual(identity.standardizedPath, "/tmp/library")
        XCTAssertEqual(context.expectedRevision, 9)
        XCTAssertTrue(context.access.isReadOnly)
        XCTAssertEqual(ImportFolderSkippedRule(label: "hidden", count: 2).id, "hidden")
        XCTAssertEqual(ImportFolderScanError(path: "a", message: "b").id, "a::b")
        XCTAssertEqual(MainSearchEntryContext.sidebar("docs"), .sidebar("docs"))
        XCTAssertEqual(MainSearchExitContext.smartList(id: 3, name: "Recent"), .smartList(id: 3, name: "Recent"))
    }

    @MainActor
    func testLibrarySelectionModelOwnsWindowLocalSelection() {
        let model = MainSelectionModel()
        model.fileIDs = [3, 7]
        model.pendingMovedFileFocusID = 7

        XCTAssertEqual(model.fileIDs, [3, 7])
        XCTAssertEqual(model.pendingMovedFileFocusID, 7)
    }
}

private struct LocalModelContractReader: CoreLocalModelStatusReading {
    func getLocalModelStatus(
        repoPath _: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        LocalModelStatusState(
            modelID: request.modelID,
            storageLocation: request.storageLocation,
            availability: .ready,
            version: "1",
            sizeBytes: 42,
            lastError: nil,
            recommendedAction: .none,
            lastCheckedAt: 100,
            diagnosticsSummary: "ready",
            featureStatuses: []
        )
    }

    func locateLocalModelFolder(
        repoPath _: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        LocalModelFolderLocationState(
            modelID: request.modelID,
            folderPath: request.storageLocation,
            exists: true,
            readable: true,
            openable: true,
            unavailableReason: nil
        )
    }
}
