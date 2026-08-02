import XCTest

final class MacOSFeatureDependencyGovernanceTests: MacOSGovernanceTestCase {
    func testFeatureLiveConvenienceEntriesStayOutsideProductionTarget() throws {
        let defaultsFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureDependencyDefaults.swift"
        })
        let source = try String(contentsOf: defaultsFile, encoding: .utf8)

        XCTAssertFalse(
            source.contains("static var live") || source.contains("static let live"),
            "Feature dependency .live conveniences belong to test support, never the production target."
        )
    }

    func testHighRiskFeatureEntryPointsRequireExplicitDependencyInjection() throws {
        let guardedPaths = Set([
            "Features/Import/ImportEntrySheetView.swift",
            "Features/Onboarding/DatabaseRepairConfirmView.swift",
            "Features/Onboarding/DatabaseRepairConfirmModel.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:ImportFeatureDependencies|OnboardingFeatureDependencies|SharedFeatureDependencies)\.live\b"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Import and database-repair entry points must receive high-risk collaborators from App composition; " +
                "tests and previews should pass explicit fixtures."
        )
    }

    func testMainListModelRequiresAnExplicitFeatureDependencyScope() throws {
        let file = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/MainList/MainFileListModel.swift"
        })
        let source = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(
            source.contains("dependencies: MainListFeatureDependencies"),
            "MainFileListModel must receive one explicit MainListFeatureDependencies scope."
        )
        XCTAssertEqual(
            try sourceRegexViolations(
                in: file,
                pattern: #"\b(?:MainListFeatureDependencies|SharedFeatureDependencies)\.live\b"#
            ),
            [],
            "MainFileListModel must not resolve production dependencies through hidden .live defaults."
        )
    }

    func testAIRouteViewsDoNotConstructHiddenLiveDependencies() throws {
        let guardedPaths = Set([
            "Features/AI/AISettingsPane.swift",
            "Features/AI/AIPrivacyRulesRoute.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:AIFeatureDependencies|SharedFeatureDependencies)\.live\b|AISettingsModel\s*\(\s*repoPath:\s*repoPath\s*\)"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "AI settings and privacy route views must receive their dependencies from the App composition " +
                "root; previews and tests should use explicit fixtures."
        )
    }

    func testProductionAIAndSearchRecoveryRoutesUseExplicitCollaborators() throws {
        let requiredSourceTerms: [String: [String]] = [
            "Features/AI/AISummaryEditorView.swift": [
                "summaryStore: aiDependencies.aiSummaryStore",
                "contentLocaleSnapshotter: aiDependencies.contentLocaleSnapshotter",
                "privacyRules: aiDependencies.aiPrivacyRules",
                "lister: aiDependencies.aiCallLogLister"
            ],
            "Features/AI/AITagSuggestionsPanel.swift": [
                "lister: aiDependencies.aiCallLogLister",
                "bridge: aiDependencies.aiPrivacyRulesManager"
            ],
            "Features/Detail/DetailTagSection.swift": [
                "aiDependencies: aiDependencies",
                "errorMapper: errorMapper"
            ],
            "Features/FileActions/BatchRenameTrigger.swift": [
                "lister: aiDependencies.aiCallLogLister",
                "bridge: aiDependencies.aiPrivacyRulesManager"
            ],
            "Features/Search/SemanticSearchMainContentSupport.swift": [
                "bridge: aiDependencies.aiPrivacyRulesManager",
                "lister: aiDependencies.aiCallLogLister",
                "aiDependencies: aiDependencies"
            ],
            "Features/Search/SemanticSearchFallbackStatusRegion.swift": [
                "statusReader: aiDependencies.localModelStatusReader",
                "bridge: aiDependencies.remoteProviderConfigurer",
                "errorMapper: errorMapper"
            ],
            "Features/Settings/AboutSettingsPane.swift": [
                "platformDifferencesModel: platformDifferencesModel"
            ],
            "Features/Settings/GeneralSettingsView.swift": [
                "contractInspector: featureDependencies.bindingContractInspector",
                "capabilityLoader: featureDependencies.platformCapabilityLoader",
                "errorMapper: sharedDependencies.errorMapper"
            ]
        ]

        for (relativePath, terms) in requiredSourceTerms {
            let file = try XCTUnwrap(productionSwiftFiles().first {
                relativeProductionPath(for: $0) == relativePath
            })
            let source = try String(contentsOf: file, encoding: .utf8)
            for term in terms {
                XCTAssertTrue(
                    source.contains(term),
                    "\(relativePath) must keep the explicit production collaborator: \(term)"
                )
            }
        }

        let forbiddenDefaultCallSites: [String: [String]] = [
            "Features/AI/AITagSuggestionsPanel.swift": [
                "AIClassificationCallLogDetailSheet(repoPath: repoPath",
                "AIClassificationPrivacyRuleReferenceSheet(repoPath: repoPath"
            ],
            "Features/FileActions/BatchRenameTrigger.swift": [
                "AIClassificationCallLogDetailSheet(repoPath: repoPath",
                "AIClassificationPrivacyRuleReferenceSheet(repoPath: repoPath"
            ],
            "Features/Search/SemanticSearchMainContentSupport.swift": [
                "AIClassificationCallLogDetailSheet(repoPath: opening.config.repoPath,",
                "AIClassificationPrivacyRuleReferenceSheet(repoPath: opening.config.repoPath,"
            ],
            "Features/Search/SemanticSearchFallbackStatusRegion.swift": [
                "LocalModelStatusModel(repoPath: repoPath)",
                "RemoteProviderConfigModel(repoPath: repoPath)"
            ]
        ]

        for (relativePath, terms) in forbiddenDefaultCallSites {
            let file = try XCTUnwrap(productionSwiftFiles().first {
                relativeProductionPath(for: $0) == relativePath
            })
            let source = try String(contentsOf: file, encoding: .utf8)
            for term in terms {
                XCTAssertFalse(
                    source.contains(term),
                    "\(relativePath) must not reintroduce the hidden default call: \(term)"
                )
            }
        }
    }
}
