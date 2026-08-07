import XCTest

final class MacOSDefaultCoreServicesGovernanceTests: MacOSGovernanceTestCase {
    func testRemainingDirectCoreBridgeDefaultsStayInventoriedForSpecializedRiskWork() throws {
        let expected: [String] = []
        let actual = try countedRegexMatches(
            in: productionSwiftFiles().filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return path != "App/AppCoreServices.swift"
                    && path != "Bridge/CoreBridge.swift"
                    && path != "App/CoreBridgeRuntimeAssembly.swift"
                    && path != "App/AreaMatrixAppSmokeTests.swift"
            },
            pattern: #"\bCoreBridge\s*\("#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Direct default CoreBridge construction must stay out of production defaults; " +
                "all lifecycle callers should resolve through an explicit dependency scope."
        )
    }

    func testImportEntryHighRiskWriteDefaultsStayExplicitAndLimited() throws {
        let importEntryFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Import/ImportEntrySheetView.swift"
        })
        let actual = try sourceRegexMatches(
            in: importEntryFile,
            pattern: [
                #"\bfileImporter: any CoreFileImporting\s*=\s*CoreBridge\s*\("#,
                #"\bbatchFileImporter: any CoreBatchCopyImporting\s*=\s*CoreBridge\s*\("#,
                #"\bbatchConflictBatcher: any CoreImportConflictBatching\s*=\s*CoreBridge\s*\("#
            ].joined(separator: "|")
        )
        XCTAssertEqual(
            actual,
            [],
            "ImportEntrySheetView must resolve all Core write capabilities through ImportFeatureDependencies."
        )
    }

    func testDatabaseRepairHighRiskDefaultsStayExplicitAndLimited() throws {
        let repairConfirmFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Onboarding/DatabaseRepairConfirmView.swift"
        })
        let actual = try sourceRegexMatches(
            in: repairConfirmFile,
            pattern: [
                #"\bmetadataRepairer: any CoreMetadataRepairing\s*=\s*CoreBridge\s*\("#,
                #"\bstartupRecoverer: any CoreStartupRecovering\s*=\s*CoreBridge\s*\("#
            ].joined(separator: "|")
        )
        XCTAssertEqual(
            actual,
            [],
            "DB repair must resolve Core capabilities through OnboardingFeatureDependencies."
        )
    }

    func testMainListDefaultCoreServicesStayCentralized() throws {
        let guardedPaths = Set([
            "Features/MainList/MainFileListModel.swift",
            "Views/Main/MainRepositoryContentView.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "MainList default Core services should be constructed through AppCoreServices, " +
                "while tests can still inject explicit doubles."
        )
    }

    func testSettingsDefaultCoreServicesStayCentralized() throws {
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0).hasPrefix("Features/Settings/") }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Settings default Core services should be constructed through AppCoreServices, " +
                "while tests can still inject explicit doubles."
        )
    }

    func testLowRiskAIDefaultCoreServicesStayCentralized() throws {
        let guardedPaths = Set([
            "Features/AI/AIClassificationCallLogDetail.swift",
            "Features/AI/AIClassificationCallLogDetailSheet.swift",
            "Features/AI/AIClassificationPrivacyRuleReference.swift",
            "Features/AI/AIClassificationSuggestionApplyState.swift",
            "Features/AI/AIClassificationSuggestionPanelModel.swift",
            "Features/AI/AIPrivacyRulesRegistryReader.swift",
            "Features/AI/AISettingsModel.swift",
            "Features/AI/AISummaryEditorState.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Low-risk AI default Core services should be constructed through AppCoreServices, " +
                "while remote AI, credential, and privacy-rule write paths remain separately governed."
        )
    }

    func testRemoteAIAndPrivacyWriteDefaultsStayExplicitAndLimited() throws {
        let guardedPatternsByPath = [
            "Features/AI/AIPrivacyRulesModel.swift":
                #"\brulesManager: any CoreAIPrivacyRulesManaging\s*=\s*CoreBridge\s*\("#,
            "Features/AI/RemoteProviderConfigModel.swift":
                #"\bbridge: any CoreRemoteProviderConfiguring\s*=\s*CoreBridge\s*\("#,
            "Features/AI/RemoteProviderConfigState.swift":
                #"\bbridge: any CoreAIPrivacyRulesManaging\s*=\s*CoreBridge\s*\("#
        ]
        var actual: [String] = []
        let guardedFiles = try productionSwiftFiles().filter {
            guardedPatternsByPath.keys.contains(relativeProductionPath(for: $0))
        }
        for fileURL in guardedFiles {
            let relativePath = relativeProductionPath(for: fileURL)
            let pattern = try XCTUnwrap(guardedPatternsByPath[relativePath])
            actual += try sourceRegexMatches(in: fileURL, pattern: pattern)
        }
        actual.sort()

        XCTAssertEqual(
            actual,
            [],
            "Remote AI and privacy-rule write defaults must resolve through AIFeatureDependencies."
        )
    }

    func testPrivacyRuleReferenceDefaultCoreServiceStaysReadOnly() throws {
        let guardedPaths = Set([
            "Features/AI/AIClassificationPrivacyRuleReference.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bupdateAIPrivacyRules\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "AI privacy rule reference views may read the privacy rules snapshot through AppCoreServices, " +
                "but privacy-rule writes must remain in the dedicated AI privacy rule editor path."
        )
    }

    func testSearchDefaultCoreServicesStayCentralized() throws {
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0).hasPrefix("Features/Search/") }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Search default Core services should be constructed through AppCoreServices, " +
                "while tests can still inject explicit doubles."
        )
    }

    func testRemoteProviderReadOnlyDefaultCoreServicesStayCentralized() throws {
        let guardedPaths = Set([
            "Features/AI/AIPrivacyRemoteProviderStateModel.swift"
        ])
        let guardedFiles = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
        let constructionViolations = try guardedFiles
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()
        let writeCapabilityViolations = try guardedFiles
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:testRemoteProvider|enableRemoteProvider|disableRemoteProvider)\s*\("#
                )
            }
            .sorted()

        XCTAssertEqual(
            constructionViolations,
            [],
            "Remote provider read-only default Core services should be constructed through AppCoreServices."
        )
        XCTAssertEqual(
            writeCapabilityViolations,
            [],
            "AIPrivacyRemoteProviderStateModel must stay read-only; remote provider test/enable/disable " +
                "paths remain separately governed."
        )
    }

    func testSearchRouteViewsDoNotConstructHiddenLiveDependencies() throws {
        let guardedPaths = Set([
            "Features/Search/SavedSearchSheetRouteView.swift",
            "Features/Search/SmartListManagementSheet.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:SearchFeatureDependencies|SharedFeatureDependencies)\.live\b"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Search route views must receive saved-search and query dependencies from App composition " +
                "or an explicit Preview/Test fixture."
        )
    }

    func testSyncConflictModelsDoNotConstructHiddenLiveDependencies() throws {
        let guardedPaths = Set([
            "Features/SyncConflicts/ICloudConflictListModel.swift",
            "Features/SyncConflicts/ICloudConflictMinimalValidation.swift",
            "Features/SyncConflicts/SyncConflictEntryModel.swift",
            "Features/SyncConflicts/SyncConflictReviewModel.swift",
            "Features/SyncConflicts/ICloudConflictListView.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bSyncConflictsFeatureDependencies\.live\b|\bSharedFeatureDependencies\.live\b"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "SyncConflicts models and route views must receive Core and error-mapping capabilities " +
                "through the feature composition boundary."
        )
    }

    func testLowRiskFileActionsDefaultCoreServicesStayCentralized() throws {
        let guardedPaths = Set([
            "Features/FileActions/ClassifierImpactPreviewSheet.swift",
            "Features/FileActions/ClassifierRuleHandoffRouteView.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Low-risk FileActions default Core services should be constructed through AppCoreServices, " +
                "while iCloud conflict routing and other high-risk paths remain separately governed."
        )
    }

    func testFileActionRoutingViewDefaultCoreServicesStayCentralized() throws {
        let guardedPaths = Set([
            "Features/FileActions/MainFileActionRoutingSupport.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "File action routing view support should receive iCloud conflict default Core services " +
                "through AppCoreServices; conflict apply behavior remains separately governed."
        )
    }
}

final class AppShellCoreServiceGovernanceTests: MacOSGovernanceTestCase {
    func testAppShellHighRiskDefaultsStayExplicitAndLimited() throws {
        let appShellFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppShellModel.swift"
        })
        let actual = try sourceRegexMatches(
            in: appShellFile,
            pattern: [
                #"\brepositoryInitializer: any CoreRepositoryInitializing\s*=\s*CoreBridge\s*\("#,
                #"\bimportProgressImporter: any CoreFileImporting\s*=\s*CoreBridge\s*\("#,
                #"\bstartupRecoverer: any CoreStartupRecovering\s*=\s*CoreBridge\s*\("#,
                #"\bexternalChangesSyncer: any CoreExternalChangesSyncing\s*=\s*CoreBridge\s*\("#
            ].joined(separator: "|")
        )
        XCTAssertEqual(
            actual,
            [],
            "AppShellModel defaults must use the process-scoped CoreBridge runtime; tests and special " +
                "lifecycle scenarios should inject an isolated bridge explicitly."
        )
        let source = try String(contentsOf: appShellFile, encoding: .utf8)
        for dependency in [
            "repositoryInitializer: any CoreRepositoryInitializing = AppCoreServices.repositoryInitializer",
            "importProgressImporter: any CoreFileImporting = AppCoreServices.importProgressImporter",
            "startupRecoverer: any CoreStartupRecovering = AppCoreServices.startupRecoverer",
            "externalChangesSyncer: any CoreExternalChangesSyncing = AppCoreServices.externalChangesSyncer"
        ] {
            XCTAssertTrue(
                source.contains(dependency),
                "AppShellModel lifecycle defaults must resolve through AppCoreServices: \(dependency)"
            )
        }
    }
}

final class ImportCoreServiceGovernanceTests: MacOSGovernanceTestCase {
    func testImportBatchConflictWriteDefaultStaysExplicitAndLimited() throws {
        let batchCopyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Import/ImportBatchCopyImportModel.swift"
        })
        let actual = try sourceRegexMatches(
            in: batchCopyFile,
            pattern: #"\bconflictBatcher: any CoreImportConflictBatching\s*=\s*CoreBridge\s*\("#
        )

        XCTAssertEqual(
            actual,
            [],
            "ImportBatchCopyImportModel must resolve conflict batching through ImportFeatureDependencies."
        )
    }

    func testImportBatchCollaboratorsAreRequiredAtCompositionBoundary() throws {
        let batchCopyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Import/ImportBatchCopyImportModel.swift"
        })
        let actual = try sourceRegexMatches(
            in: batchCopyFile,
            pattern: [
                #"\bconflictBatcher: any CoreImportConflictBatching\s*=\s*"#,
                #"\bundoActionStore: any CoreUndoActionLogging\s*=\s*"#,
                #"\bsessionStore: any ImportBatchSessionPersisting\s*=\s*"#,
                #"\bplaceholderDownloader: any ICloudPlaceholderDownloading\s*=\s*"#
            ].joined(separator: "|")
        )

        XCTAssertEqual(
            actual,
            [],
            "Batch import must receive Core, persistence, and platform collaborators from App composition " +
                "instead of constructing hidden production defaults."
        )
    }
}

final class SyncConflictCoreServiceGovernanceTests: MacOSGovernanceTestCase {
    func testSyncConflictReadOnlyDefaultCoreServicesStayCentralized() throws {
        let guardedPaths = Set([
            "Features/SyncConflicts/ICloudConflictListModel.swift",
            "Features/SyncConflicts/SyncConflictEntryModel.swift"
        ])
        let guardedFiles = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
        let constructionViolations = try guardedFiles
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bCoreBridge\s*\("#)
            }
            .sorted()
        let writeCapabilityViolations = try guardedFiles
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:preview|resolve|apply)[A-Za-z]*(?:SyncConflict|ICloudConflict)\s*\("#
                )
            }
            .sorted()

        XCTAssertEqual(
            constructionViolations,
            [],
            "SyncConflict read-only default Core services should be constructed through AppCoreServices."
        )
        XCTAssertEqual(
            writeCapabilityViolations,
            [],
            "SyncConflict entry/list models must stay read-only; preview, resolve, and apply paths remain " +
                "separately governed."
        )
    }

    func testSyncConflictResolutionWriteDefaultStaysExplicitAndLimited() throws {
        let reviewModelFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/SyncConflicts/SyncConflictReviewModel.swift"
        })
        let actual = try sourceRegexMatches(
            in: reviewModelFile,
            pattern: #"\bconflictResolver: any CoreSyncConflictResolving\s*=\s*CoreBridge\s*\("#
        )

        XCTAssertEqual(
            actual,
            [],
            "SyncConflictReviewModel must resolve conflict writes through SyncConflictsFeatureDependencies."
        )
    }
}
