@testable import AreaMatrix
import XCTest

final class AreaMatrixDeveloperScenarioTests: XCTestCase {
    func testScenarioConfigurationResolvesIndependentAxes() throws {
        let configuration = try XCTUnwrap(AreaMatrixDeveloperScenario.resolve(environment: [
            "AREAMATRIX_SCENARIO": "sync-conflict",
            "AREAMATRIX_SCENARIO_THEME": "dark",
            "AREAMATRIX_SCENARIO_LOCALE": "zh-Hans",
            "AREAMATRIX_SCENARIO_VIEWPORT": "compact"
        ]))

        XCTAssertEqual(configuration.scenario, .syncConflict)
        XCTAssertEqual(configuration.theme, .dark)
        XCTAssertEqual(configuration.language, .zhHans)
        XCTAssertEqual(configuration.viewport, .compact)
    }

    func testLegacyDarkScenarioAliasesRemainCompatible() throws {
        let configuration = try XCTUnwrap(AreaMatrixDeveloperScenario.resolve(environment: [
            "AREAMATRIX_SCENARIO": "ui-catalog-dark"
        ]))

        XCTAssertEqual(configuration.scenario, .uiCatalog)
        XCTAssertEqual(configuration.theme, .dark)
    }

    func testDeveloperScenarioInventoryCoversRequiredCriticalStates() {
        XCTAssertEqual(
            AreaMatrixDeveloperScenario.allCases.map(\.rawValue),
            Self.expectedScenarioIdentifiers
        )

        let required: Set<AreaMatrixDeveloperScenario> = [
            .onboarding,
            .repositoryEmpty,
            .permissionFailure,
            .databaseCorrupt,
            .iCloudPlaceholder,
            .importConflict,
            .syncConflict,
            .aiUnavailable
        ]
        XCTAssertTrue(required.isSubset(of: Set(AreaMatrixDeveloperScenario.allCases)))
    }

    func testScenarioInventoryCoversEveryCommonStateKind() {
        XCTAssertEqual(
            Set(AreaMatrixDeveloperScenario.allCases.map(\.stateKind)),
            Set(AreaMatrixPreviewStateKind.allCases)
        )
        XCTAssertEqual(Set(AreaMatrixPreviewTheme.allCases), [.light, .dark])
        XCTAssertEqual(Set(AreaMatrixPreviewLanguage.allCases), [.en, .zhHans])
        XCTAssertEqual(Set(AreaMatrixPreviewViewport.allCases), [.compact, .standard, .wide])
    }

    func testStableProductSurfaceInventoryIsUniqueAndFeatureOwned() {
        let inventory = AreaMatrixDeveloperSurfaceInventory.all

        XCTAssertEqual(Set(inventory.map(\.id)).count, inventory.count)
        XCTAssertEqual(
            Set(inventory.map(\.feature)),
            Set(AreaMatrixDeveloperSurfaceFeature.allCases)
        )
        XCTAssertTrue(inventory.allSatisfy { surface in
            surface.scenarios.allSatisfy { $0 != .launcher && $0 != .uiCatalog }
        })
    }

    func testFullPageScenarioCoverageCannotRegressOrHideSurfaces() {
        let baselineSurfaceCount = 61
        let inventory = AreaMatrixDeveloperSurfaceInventory.all

        XCTAssertGreaterThanOrEqual(
            inventory.count,
            baselineSurfaceCount,
            "Stable product surfaces cannot be deleted from the inventory to inflate coverage."
        )
        XCTAssertTrue(
            AreaMatrixDeveloperSurfaceInventory.uncovered.isEmpty,
            "Every stable product surface must have a full-page Scenario."
        )
        XCTAssertEqual(
            Set(AreaMatrixDeveloperSurfaceInventory.covered.map(\.id)),
            Self.expectedCoveredSurfaceIDs
        )
    }

    func testUnknownScenarioFailsClosedToNormalApplication() {
        XCTAssertNil(
            AreaMatrixDeveloperScenario.resolve(environment: ["AREAMATRIX_SCENARIO": "unknown"])
        )
    }

    @MainActor
    func testLanguageFixturesCoverFourUniqueResolvedCombinations() throws {
        let fixtures = AreaMatrixPreviewFixtures.languageCombinations

        XCTAssertEqual(fixtures.count, 4)
        XCTAssertEqual(fixtures.map(\.id), [
            "en-en",
            "en-zh-Hans",
            "zh-Hans-en",
            "zh-Hans-zh-Hans"
        ])
        XCTAssertEqual(Set(fixtures.map { "\($0.interfaceIdentifier)|\($0.contentIdentifier)" }).count, 4)

        for fixture in fixtures {
            let runtime = AppLanguageRuntime(selection: fixture.interfaceLanguage)
            let localizer = AppLocalizer(runtime: runtime)
            XCTAssertEqual(runtime.resolvedIdentifier(preferredLanguages: ["fr-FR"]), fixture.interfaceIdentifier)
            XCTAssertEqual(localizer.resourceLocaleIdentifier, fixture.interfaceIdentifier)
            XCTAssertEqual(
                try fixture.contentLanguage.resolvedIdentifier(
                    interfaceLocaleIdentifier: fixture.interfaceIdentifier
                ),
                fixture.contentIdentifier
            )
        }
    }

    @MainActor
    func testLanguageFixturesResolveBothCatalogResources() {
        let english = AppLocalizer(runtime: AppLanguageRuntime(selection: .en))
        let simplifiedChinese = AppLocalizer(runtime: AppLanguageRuntime(selection: .zhHans))

        XCTAssertEqual(english.string("settings.language.interface.title"), "Interface language")
        XCTAssertEqual(english.string("settings.language.content.title"), "Repository content language")
        XCTAssertEqual(simplifiedChinese.string("settings.language.interface.title"), "界面语言")
        XCTAssertEqual(simplifiedChinese.string("settings.language.content.title"), "资料库内容语言")
    }

    @MainActor
    func testCatalogAndLauncherBodiesCanBeConstructed() {
        _ = AreaMatrixUICatalog().body
        _ = AreaMatrixDeveloperScenarioLauncher().body
    }

    @MainActor
    func testEveryDeveloperScenarioBodyCanBeConstructedWithoutRepositoryIO() {
        for scenario in AreaMatrixDeveloperScenario.allCases where scenario != .launcher {
            _ = AreaMatrixDeveloperScenarioContent(scenario: scenario).body
        }
    }

    func testLargeDataFixtureIsDeterministicAndExercisesMixedStates() {
        let rows = AreaMatrixPreviewFixtures.fileRows(count: 120)

        XCTAssertEqual(rows.count, 120)
        XCTAssertEqual(Set(rows.map(\.id)).count, 120)
        XCTAssertTrue(rows.contains { $0.status.isFailed })
        XCTAssertTrue(rows.contains { $0.isConflictReviewRow })
    }

    func testSearchScenarioCoreFixtureIsDeterministicAndInMemory() async throws {
        let core = DeveloperSearchCoreFixture()
        let savedSearches = try await core.listSavedSearches(repoPath: DeveloperSearchScenarioFixture.repoPath)
        let page = try await core.searchFiles(
            repoPath: DeveloperSearchScenarioFixture.repoPath,
            request: DeveloperSearchScenarioFixture.filteredRequest
        )

        XCTAssertEqual(savedSearches, [DeveloperSearchScenarioFixture.savedSearch])
        XCTAssertEqual(page.query, DeveloperSearchScenarioFixture.filteredRequest.query)
        XCTAssertEqual(page.totalCount, 12)
        XCTAssertEqual(page.indexStatus, .ready)
    }

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

    func testFileActionScenarioFixturesAreDeterministicAndInMemory() async throws {
        let core = DeveloperFileActionCoreFixture()
        let fixture = DeveloperFileActionScenarioFixture.self
        let fileIDs = fixture.selectedFiles.map(\.id)
        let tags = try await core.listTags(repoPath: fixture.repoPath, fileID: fixture.primaryFile.id)
        let deletePreview = try await core.previewBatchDelete(
            repoPath: fixture.repoPath,
            fileIDs: fileIDs,
            deleteMode: .moveToTrash
        )
        let categoryPreview = try await core.previewBatchMoveToCategory(
            repoPath: fixture.repoPath,
            fileIDs: fileIDs,
            targetCategory: "finance",
            moveRepoOwnedFiles: true
        )
        let impact = try await core.previewClassifierRuleImpact(
            repoPath: fixture.repoPath,
            request: ClassifierImpactPreviewRequestSnapshot(
                mode: .ruleDraft,
                rule: ClassifierRuleSnapshot.testFixture(
                    targetCategory: "finance",
                    keywords: ["quarterly"],
                    extensions: ["pdf"],
                    priority: 25,
                    previewConfirmed: true
                ),
                moveFiles: true,
                replacementCategory: nil
            )
        )

        XCTAssertEqual(tags, fixture.tagSet)
        XCTAssertEqual(deletePreview.requestedFileCount, 3)
        XCTAssertEqual(deletePreview.indexOnlyCount, 1)
        XCTAssertEqual(categoryPreview.requestedFileCount, 3)
        XCTAssertEqual(categoryPreview.metadataOnlyCount, 1)
        XCTAssertEqual(impact.samples.count, 3)
        XCTAssertFalse(impact.canApply)
    }

    func testImportScenarioFixturesAreDeterministicAndInMemory() async throws {
        let services = DeveloperImportScenarioServices()
        let fixture = DeveloperImportScenarioFixture.self
        let request = ImportSingleFilePreflightRequest(
            repoPath: fixture.repoPath,
            sourceURL: fixture.singleFileRequest.urls[0],
            category: "docs",
            targetFilename: "quarterly-report.pdf"
        )

        let prediction = try await services.predictCategory(
            repoPath: fixture.repoPath,
            filename: "invoice-2026.pdf"
        )
        let scan = await services.scanFolder(
            rootURL: fixture.sourceRoot,
            includeHiddenFiles: false,
            followSymlinks: false
        )
        let preflight = await services.preflightSingleFileImport(request: request)

        XCTAssertEqual(prediction.category, "finance")
        XCTAssertEqual(scan.rows, fixture.folderRows)
        XCTAssertEqual(scan.folderCount, 2)
        XCTAssertEqual(preflight.targetRelativePath, "docs/quarterly-report.pdf")
        XCTAssertEqual(preflight.conflict, .none)
    }

    func testMainListScenarioFixtureIsDeterministicAndInMemory() async throws {
        let core = DeveloperMainListCoreFixture()
        let files = try await core.listFiles(
            repoPath: DeveloperMainListScenarioFixture.repoPath,
            filter: .currentCategory(nil)
        )
        let tree = try await core.listTree(
            repoPath: DeveloperMainListScenarioFixture.repoPath,
            locale: "en"
        )

        XCTAssertEqual(files, DeveloperFileActionScenarioFixture.selectedFiles)
        XCTAssertEqual(tree, DeveloperMainListScenarioFixture.opening.tree)
    }

    func testSyncConflictScenarioFixtureIsDeterministicAndInMemory() async throws {
        let core = DeveloperSyncConflictCoreFixture()
        let iCloudConflicts = try await core.listICloudConflicts(
            repoPath: DeveloperSyncConflictScenarioFixture.repoPath
        )
        let syncConflicts = try await core.detectSyncConflicts(repoPath: DeveloperSyncConflictScenarioFixture.repoPath)
        let validation = try await core.validateRepoPath(repoPath: DeveloperSyncConflictScenarioFixture.repoPath)

        XCTAssertEqual(iCloudConflicts, [DeveloperSyncConflictScenarioFixture.iCloudPair])
        XCTAssertEqual(syncConflicts, [DeveloperSyncConflictScenarioFixture.syncConflict])
        XCTAssertTrue(validation.isInitialized)
        XCTAssertTrue(validation.isICloudPath)
    }
}

private extension AreaMatrixDeveloperScenarioTests {
    static let expectedCoveredSurfaceIDs: Set<String> = [
        "AI.AICallLogView",
        "AI.AIClassificationSuggestionPanel",
        "AI.AIPrivacyRulesRouteView",
        "AI.AISettingsPane",
        "AI.AISummaryEditorView",
        "AI.AITagSuggestionsPanel",
        "AI.LocalModelStatusView",
        "AI.RemoteModelConfigSheet",
        "CommandPalette.CommandPaletteView",
        "Detail.DetailLogTabView",
        "Detail.DetailNoteTabView",
        "Detail.MainRepositoryDetailPane",
        "Detail.MultiSelectionDetailSummary",
        "Diagnostics.DiagnosticsConsoleView",
        "Diagnostics.DiagnosticsPackagePreviewSheet",
        "Diagnostics.DiagnosticsSettingsPane",
        "FileActions.BatchAddTagsSheet",
        "FileActions.BatchChangeCategorySheet",
        "FileActions.BatchDeleteConfirmSheet",
        "FileActions.BatchRenameSheet",
        "FileActions.ChangeCategorySheet",
        "FileActions.ClassifierImpactPreviewSheet",
        "FileActions.DeleteFileConfirmSheet",
        "FileActions.RenameFileSheet",
        "FileActions.ReplaceConfirmSheet",
        "FileActions.TagSuggestionsPanel",
        "FileActions.UndoHistoryPanel",
        "Import.ImportEntrySheetView",
        "Import.ImportFolderPreviewView",
        "Import.ImportProgressView",
        "Import.ImportResultView",
        "MainList.MainRepositoryContentView",
        "Onboarding.ConfirmInitStepView",
        "Onboarding.DBRepairConfirmView",
        "Onboarding.InitDoneStepView",
        "Onboarding.InitFailedStepView",
        "Onboarding.InitializingStepView",
        "Onboarding.MainLoadingView",
        "Onboarding.StartupRecoveryErrorRecoveryView",
        "Onboarding.ValidatePathStepView",
        "Onboarding.WelcomeStepView",
        "RepositoryLifecycle.MainRepoErrorView",
        "Search.QueryErrorRouteView",
        "Search.SavedSearchSheetRouteView",
        "Search.SearchEmptyRouteView",
        "Search.SearchIndexingStatusRouteView",
        "Search.SemanticSearchResultsView",
        "Search.SmartListManagementSheet",
        "Settings.AboutSettingsPane",
        "Settings.AdvancedSettingsPane",
        "Settings.ClassifierSettingsPane",
        "Settings.GeneralSettingsView",
        "Settings.IntegrationsSettingsPane",
        "Settings.LanguageSettingsPane",
        "Settings.PlatformDifferencesView",
        "Settings.RepositorySettingsPane",
        "SyncConflicts.ICloudConflictListView",
        "SyncConflicts.ICloudConflictMinimalSheet",
        "SyncConflicts.SyncConflictEntryPanel",
        "SyncConflicts.SyncConflictReplaceConfirmationPanel",
        "SyncConflicts.SyncConflictReviewView"
    ]

    static let expectedScenarioIdentifiers = [
        "launcher",
        "ui-catalog",
        "command-palette",
        "detail-log",
        "detail-note",
        "detail-pane",
        "detail-multi-selection",
        "diagnostics-console",
        "diagnostics-package-preview",
        "diagnostics-settings",
        "onboarding",
        "onboarding-confirm",
        "onboarding-database-repair",
        "onboarding-done",
        "onboarding-failed",
        "onboarding-initializing",
        "onboarding-recovery",
        "onboarding-validate-path",
        "loading",
        "repository-empty",
        "repository-ready",
        "permission-failure",
        "database-corrupt",
        "icloud-placeholder",
        "import-conflict",
        "import-entry",
        "import-folder-preview",
        "import-progress",
        "import-result",
        "main-repository-content",
        "sync-conflict",
        "sync-conflicts-icloud-list",
        "sync-conflicts-icloud-minimal",
        "sync-conflicts-entry",
        "sync-conflicts-replace-confirmation",
        "sync-conflicts-review",
        "ai-unavailable",
        "ai-call-log",
        "ai-classification-suggestion",
        "ai-privacy-rules",
        "ai-settings",
        "ai-summary-editor",
        "ai-tag-suggestions",
        "ai-local-model-status",
        "ai-remote-model-config",
        "disabled",
        "stale-data",
        "long-content",
        "large-data",
        "search-query-error",
        "search-saved-search",
        "search-empty",
        "search-index-status",
        "search-semantic-results",
        "search-smart-list",
        "file-actions-batch-add-tags",
        "file-actions-batch-change-category",
        "file-actions-batch-delete",
        "file-actions-batch-rename",
        "file-actions-change-category",
        "file-actions-classifier-impact",
        "file-actions-delete",
        "file-actions-rename",
        "file-actions-replace",
        "file-actions-tag-suggestions",
        "file-actions-undo-history",
        "settings-about",
        "settings-advanced",
        "settings-classifier",
        "settings-general",
        "settings-integrations",
        "settings-language",
        "settings-platform-differences",
        "settings-repository"
    ]
}
