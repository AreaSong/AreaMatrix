import XCTest

final class MacOSDefaultCoreServicesGovernanceTests: MacOSGovernanceTestCase {
    func testRemainingDirectCoreBridgeDefaultsStayInventoriedForSpecializedRiskWork() throws {
        let expected = [
            "App/AppShellModel.swift:CoreBridge(:4",
            "Features/AI/AIPrivacyRulesModel.swift:CoreBridge(:1",
            "Features/AI/RemoteProviderConfigModel.swift:CoreBridge(:1",
            "Features/AI/RemoteProviderConfigState.swift:CoreBridge(:1",
            "Features/Import/ImportBatchCopyImportModel.swift:CoreBridge(:1",
            "Features/Import/ImportEntrySheetView.swift:CoreBridge(:3",
            "Features/Onboarding/DatabaseRepairConfirmView.swift:CoreBridge(:2",
            "Features/SyncConflicts/SyncConflictReviewModel.swift:CoreBridge(:1"
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles().filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return path != "App/AppCoreServices.swift"
                    && path != "App/AreaMatrixAppSmokeTests.swift"
            },
            pattern: #"\bCoreBridge\s*\("#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Direct default CoreBridge construction should not grow; remaining entries are specialized " +
                "startup, import, repair, remote AI, privacy, or conflict-resolution risk work."
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
        let importEntryPrefix = "Features/Import/ImportEntrySheetView.swift:"

        XCTAssertEqual(
            actual,
            [
                importEntryPrefix + "fileImporter: any CoreFileImporting = CoreBridge(",
                importEntryPrefix + "batchFileImporter: any CoreBatchCopyImporting = CoreBridge(",
                importEntryPrefix + "batchConflictBatcher: any CoreImportConflictBatching = CoreBridge("
            ],
            "ImportEntrySheetView may keep direct CoreBridge defaults only for high-risk import write paths; " +
                "low-risk prediction, error mapping, platform, and session defaults should stay centralized."
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
        let repairConfirmPrefix = "Features/Onboarding/DatabaseRepairConfirmView.swift:"

        XCTAssertEqual(
            actual,
            [
                repairConfirmPrefix + "metadataRepairer: any CoreMetadataRepairing = CoreBridge(",
                repairConfirmPrefix + "startupRecoverer: any CoreStartupRecovering = CoreBridge("
            ],
            "DB repair may keep direct CoreBridge defaults only for metadata repair and startup recovery; " +
                "diagnostics and error mapping defaults should stay centralized."
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
            [
                "Features/AI/AIPrivacyRulesModel.swift:rulesManager: any CoreAIPrivacyRulesManaging = CoreBridge(",
                "Features/AI/RemoteProviderConfigModel.swift:bridge: any CoreRemoteProviderConfiguring = CoreBridge(",
                "Features/AI/RemoteProviderConfigState.swift:bridge: any CoreAIPrivacyRulesManaging = CoreBridge("
            ],
            "Remote AI and privacy-rule write defaults should stay explicit and limited; " +
                "read-only AI defaults should stay centralized through AppCoreServices."
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
        let appShellPrefix = "App/AppShellModel.swift:"

        XCTAssertEqual(
            actual,
            [
                appShellPrefix + "repositoryInitializer: any CoreRepositoryInitializing = CoreBridge(",
                appShellPrefix + "importProgressImporter: any CoreFileImporting = CoreBridge(",
                appShellPrefix + "startupRecoverer: any CoreStartupRecovering = CoreBridge(",
                appShellPrefix + "externalChangesSyncer: any CoreExternalChangesSyncing = CoreBridge("
            ],
            "AppShellModel may keep direct CoreBridge defaults only for initialization, import, startup " +
                "recovery, and external-sync lifecycle write paths; lower-risk defaults should stay centralized."
        )
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
            [
                "Features/Import/ImportBatchCopyImportModel.swift:" +
                    "conflictBatcher: any CoreImportConflictBatching = CoreBridge("
            ],
            "ImportBatchCopyImportModel may keep a direct CoreBridge default only for batch conflict " +
                "preview/apply work; session, undo, error mapping, and platform defaults should stay centralized."
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
            [
                "Features/SyncConflicts/SyncConflictReviewModel.swift:" +
                    "conflictResolver: any CoreSyncConflictResolving = CoreBridge("
            ],
            "SyncConflictReviewModel may keep a direct CoreBridge default only for preview/resolve write work; " +
                "conflict detection and error mapping defaults should stay centralized through AppCoreServices."
        )
    }
}
