import Foundation
import XCTest

final class MacOSArchitectureDebtGovernanceTests: MacOSGovernanceTestCase {
    private let typeSpanInventory = [
        TypeSpanBudget(type: "CoreBridge", owner: "CoreBridge", maximumFiles: 33, maximumExtensions: 51),
        TypeSpanBudget(type: "MainRepositoryContentView", owner: "App composition", maximumFiles: 20,
                       maximumExtensions: 21),
        TypeSpanBudget(type: "MainFileListModel", owner: "MainList", maximumFiles: 7, maximumExtensions: 8),
        TypeSpanBudget(type: "SearchModel", owner: "Search", maximumFiles: 5, maximumExtensions: 5),
        TypeSpanBudget(type: "FileActionCoordinator", owner: "FileActions", maximumFiles: 6, maximumExtensions: 5),
        TypeSpanBudget(type: "DetailTagModel", owner: "Detail", maximumFiles: 5, maximumExtensions: 5),
        TypeSpanBudget(type: "OnboardingModel", owner: "RepositoryLifecycle", maximumFiles: 17, maximumExtensions: 17),
        TypeSpanBudget(type: "ImportBatchCopyImportModel", owner: "Import", maximumFiles: 11, maximumExtensions: 11),
        TypeSpanBudget(type: "ImportSingleFilePreviewModel", owner: "Import", maximumFiles: 6, maximumExtensions: 6),
        TypeSpanBudget(type: "AppRepoConfigSnapshot", owner: "CoreBridge contract", maximumFiles: 7,
                       maximumExtensions: 6),
        TypeSpanBudget(type: "ObservabilityCatalog", owner: "Observability", maximumFiles: 5, maximumExtensions: 5),
        TypeSpanBudget(type: "FileEntrySnapshot", owner: "CoreBridge contract", maximumFiles: 5, maximumExtensions: 5)
    ]

    private let crossFeatureExtensionInventory = Set<String>()

    private let directCrossFeatureDependencyInventory: Set<String> = [
        "AI->Library",
        "AI->Operation",
        "AI->Settings",
        "Diagnostics->Settings",
        "Ingestion->Library",
        "Ingestion->Operation",
        "Library->AI",
        "Library->Ingestion",
        "Library->Operation",
        "Library->Settings",
        "Operation->AI",
        "Operation->Ingestion",
        "Operation->Library",
        "Operation->Settings",
        "Settings->AI",
        "Settings->Diagnostics",
        "Settings->Operation"
    ]

    func testWideTypesCannotSpanMoreFilesOrExtensions() throws {
        let spans = try typeSpans(in: allProductionSwiftFiles())
        let wideTypes = Set(spans.filter { $0.value.extensionCount >= 5 }.map(\.key))
        XCTAssertEqual(wideTypes, Set(typeSpanInventory.map(\.type)))

        let violations = typeSpanInventory.compactMap { budget -> String? in
            guard let span = spans[budget.type] else { return "\(budget.type):missing" }
            guard span.fileCount > budget.maximumFiles || span.extensionCount > budget.maximumExtensions else {
                return nil
            }
            return "\(budget.type):files=\(span.fileCount)/\(budget.maximumFiles)," +
                "extensions=\(span.extensionCount)/\(budget.maximumExtensions)"
        }
        XCTAssertEqual(violations, [], "Wide logical types must shrink before they can grow.")
    }

    func testWideTypeBudgetsDocumentOwnership() {
        XCTAssertEqual(
            typeSpanInventory.filter { $0.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.type),
            [],
            "Every wide type budget must name its architectural owner."
        )
    }

    func testCrossFeatureExtensionsAreAnExactShrinkingInventory() throws {
        XCTAssertEqual(
            try crossFeatureExtensions(),
            crossFeatureExtensionInventory,
            "A Feature must not extend a type owned by another Feature. " +
                "Remove existing entries as facades replace them."
        )
    }

    func testDirectCrossFeatureDependenciesAreAnExactShrinkingInventory() throws {
        XCTAssertEqual(
            try directCrossFeatureDependencies(),
            directCrossFeatureDependencyInventory,
            "Direct references to another Feature's concrete types may only shrink. " +
                "Move shared contracts to a Package or inject a feature-owned facade before removing an edge."
        )
    }

    func testFeaturePackageTargetsAreRealAndDoNotDependOnEachOther() throws {
        let macOSRoot = testsDirectory().deletingLastPathComponent()
        let packageFile = macOSRoot.appendingPathComponent("Packages/AreaMatrixModules/Package.swift")
        let packageSource = try String(contentsOf: packageFile, encoding: .utf8)
        let featureTargets = [
            "AreaMatrixFeatureLibrary",
            "AreaMatrixFeatureIngestion",
            "AreaMatrixFeatureOperation",
            "AreaMatrixFeatureSettings",
            "AreaMatrixFeatureAI"
        ]

        for target in featureTargets {
            let declaration = ".target(\n            name: \"\(target)\","
            let start = try XCTUnwrap(packageSource.range(of: declaration), "Missing SwiftPM target: \(target)")
            let remainder = packageSource[start.lowerBound...]
            let end = try XCTUnwrap(remainder.range(of: "\n        ),"), "Malformed SwiftPM target: \(target)")
            let targetBlock = String(remainder[..<end.upperBound])

            XCTAssertTrue(targetBlock.contains("\"AreaMatrixCoreContracts\""))
            for otherTarget in featureTargets where otherTarget != target {
                XCTAssertFalse(targetBlock.contains(otherTarget), "\(target) must not depend on \(otherTarget).")
            }
            let targetSources = try packageSwiftFiles(target)
                .map { try String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n")
            for otherTarget in featureTargets where otherTarget != target {
                XCTAssertFalse(
                    targetSources.contains("import \(otherTarget)"),
                    "\(target) sources must not import \(otherTarget)."
                )
            }
            XCTAssertFalse(
                try packageSwiftFiles(target).isEmpty,
                "\(target) must contain real production source, not an empty target."
            )
        }

        let compositionSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("App/FeatureManifest.swift"),
            encoding: .utf8
        )
        for target in featureTargets {
            XCTAssertTrue(compositionSource.contains("import \(target)"))
        }
    }

    func testFeaturePackageMigrationMovesOnlyTowardPhysicalOwnership() throws {
        let appFeatureRoot = productionDirectory().appendingPathComponent("Features", isDirectory: true)
        let appFeatureFileCount = try productionSwiftFiles().filter {
            $0.path.hasPrefix(appFeatureRoot.path + "/")
        }.count
        let packageFeatureFileCount = try [
            "AreaMatrixFeatureLibrary",
            "AreaMatrixFeatureIngestion",
            "AreaMatrixFeatureOperation",
            "AreaMatrixFeatureSettings",
            "AreaMatrixFeatureAI"
        ].reduce(into: 0) { count, target in
            count += try packageSwiftFiles(target).count
        }

        XCTAssertLessThanOrEqual(appFeatureFileCount, 330, "App-owned Feature sources may only shrink.")
        XCTAssertGreaterThanOrEqual(packageFeatureFileCount, 31, "Package-owned Feature sources may only grow.")
    }

    func testMigratedFeatureSourcesAndDirectTestDependenciesCannotRegress() throws {
        try assertMigratedFeatureDependencies(
            productionDirectory: productionDirectory(),
            macOSDirectory: testsDirectory().deletingLastPathComponent()
        )
    }

    func testCommandPaletteModelCannotReturnToMainListOwnership() throws {
        let mainListFile = productionDirectory()
            .appendingPathComponent("Features/MainList/MainFileListModel.swift")
        let assemblyFile = productionDirectory()
            .appendingPathComponent("App/MainRepositoryContentAssembly.swift")
        let contentViewFile = productionDirectory()
            .appendingPathComponent("Views/Main/MainRepositoryContentView.swift")
        let mainListSource = try String(contentsOf: mainListFile, encoding: .utf8)
        let assemblySource = try String(contentsOf: assemblyFile, encoding: .utf8)
        let contentViewSource = try String(contentsOf: contentViewFile, encoding: .utf8)

        XCTAssertFalse(mainListSource.contains("CommandPaletteModel"))
        XCTAssertFalse(mainListSource.contains("commandPaletteState"))
        XCTAssertFalse(mainListSource.contains("commandPaletteQuery"))
        XCTAssertTrue(assemblySource.contains("let makeCommandPaletteModel: () -> CommandPaletteModel"))
        XCTAssertTrue(contentViewSource.contains("@StateObject var commandPaletteModel: CommandPaletteModel"))
    }

    func testSearchModelCannotReturnToMainListOwnership() throws {
        let mainListSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )
        let searchSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/Search/SearchModel.swift"),
            encoding: .utf8
        )
        let contentViewSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentView.swift"),
            encoding: .utf8
        )
        let mainListSources = try productionSwiftFiles()
            .filter { $0.path.contains("/Features/MainList/") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for forbidden in [
            "@Published var state",
            "var searchGeneration",
            "var searchFacetsGeneration",
            "var semanticIndexBuildTask",
            "let searchQuerying",
            "let semanticSearching",
            "let semanticFallbackReader",
            "let searchFiltering"
        ] {
            XCTAssertFalse(mainListSource.contains(forbidden), "Search ownership returned to MainList: \(forbidden)")
            XCTAssertTrue(searchSource.contains(forbidden), "SearchModel must own: \(forbidden)")
        }
        XCTAssertTrue(contentViewSource.contains("@StateObject var searchModel: SearchModel"))
        XCTAssertTrue(contentViewSource.contains("_searchModel = StateObject(wrappedValue: fileListModel.searchModel)"))
        XCTAssertFalse(mainListSource.contains("searchModelObservation"))
        XCTAssertFalse(mainListSource.contains("searchModel.objectWillChange"))
        for forbiddenFacade in [
            "func runSearch(",
            "func loadSearchFacets(",
            "func retrySearch()",
            "func restoreSavedSearch(",
            "var searchState: MainSearchState",
            "var searchFacetsState: MainSearchFacetsState"
        ] {
            XCTAssertFalse(
                mainListSources.contains(forbiddenFacade),
                "MainList must not recreate the SearchModel facade: \(forbiddenFacade)"
            )
        }
    }
}

extension MacOSArchitectureDebtGovernanceTests {
    func testMainListDerivesOperationContextFromRepositorySession() throws {
        let source = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("var operationContext: RepositoryOperationContext"))
        XCTAssertTrue(source.contains("repositorySession.makeOperationContext()"))
        XCTAssertFalse(source.contains("let operationContext: RepositoryOperationContext"))
        XCTAssertFalse(source.contains("operationContext = session.makeOperationContext()"))
    }

    func testMainListModelDelegatesOwnedModelAssembly() throws {
        let mainListSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )
        let assemblyURL = productionDirectory()
            .appendingPathComponent("App/MainFileListOwnedModels.swift")
        let assemblySource = try String(contentsOf: assemblyURL, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: assemblyURL.path))
        XCTAssertTrue(mainListSource.contains("MainFileListOwnedModels(repoPath:"))
        XCTAssertFalse(mainListSource.contains("makeOwnedModels"))
        XCTAssertTrue(assemblySource.contains("struct MainFileListOwnedModels"))
        XCTAssertTrue(assemblySource.contains("MainListDiagnosticsModel"))
        XCTAssertTrue(assemblySource.contains("SearchModel"))
        XCTAssertTrue(assemblySource.contains("FileActionCoordinator"))
    }

    func testMainListAlgorithmsRemainOwnedByLibraryPackage() {
        let appMainList = productionDirectory().appendingPathComponent("Features/MainList")
        let packageLibrary = testsDirectory().deletingLastPathComponent()
            .appendingPathComponent("Packages/AreaMatrixModules/Sources/AreaMatrixFeatureLibrary")

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: appMainList.appendingPathComponent("MainListVisibleFileFiltering.swift").path
            )
        )
        for file in [
            "FileEntryDisplay.swift",
            "MainListProjection.swift",
            "MainListFiltering.swift",
            "MainListPagination.swift",
            "MainListLoadingState.swift"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: packageLibrary.appendingPathComponent(file).path),
                "Library Package must continue to own \(file)."
            )
        }
    }

    func testMainListLoadingStateCannotReturnToAppOwnership() throws {
        let source = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Published var loadingState = MainListLoadingState()"))
        for forbidden in [
            "@Published var isLoading",
            "@Published var hasMore",
            "@Published var isLoadingMore",
            "var nextFilePageOffset: Int64 ="
        ] {
            XCTAssertFalse(source.contains(forbidden), "Loading ownership returned to MainFileListModel: \(forbidden)")
        }
    }

    func testSidebarSelectionCannotReturnToViewLocalState() throws {
        let source = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentView.swift"),
            encoding: .utf8
        )
        let sidebarSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentSidebar.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@StateObject var sidebarSelectionModel: MainSidebarSelectionModel"))
        XCTAssertFalse(source.contains("@State var selectedSidebarID"))
        XCTAssertTrue(sidebarSource.contains("List(selection: selectedSidebarIDBinding)"))
    }

    func testSearchInputStateCannotReturnToViewLocalStorage() throws {
        let source = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@StateObject var searchInputModel: MainRepositorySearchInputModel"))
        for forbidden in [
            "@State var filterText",
            "@State var searchScope",
            "@State var searchMode",
            "@State var searchSort",
            "@State var searchFilters"
        ] {
            XCTAssertFalse(source.contains(forbidden), "Search input returned to View-local state: \(forbidden)")
        }
        XCTAssertTrue(source.contains("$searchInputModel.filterText"))
    }

    func testDetailTagFilterRegistryCannotReturnToMainListOwnership() throws {
        let mainListSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )
        let detailTagSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/Detail/DetailTagModel.swift"),
            encoding: .utf8
        )
        let contentViewSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(mainListSource.contains("@Published var tagFilterRegistryState"))
        XCTAssertFalse(mainListSource.contains("var tagFilterRegistryGeneration"))
        XCTAssertTrue(detailTagSource.contains("@Published var filterRegistryState"))
        XCTAssertTrue(detailTagSource.contains("var filterRegistryGeneration"))
        XCTAssertTrue(contentViewSource.contains("@StateObject var detailTagModel: DetailTagModel"))
    }

    func testSingleFileDetailTagStateCannotReturnToMainListOwnership() throws {
        let mainListSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )
        let detailTagSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/Detail/DetailTagModel.swift"),
            encoding: .utf8
        )

        for state in ["editorState", "suggestionState", "aiSuggestionState", "presentationRequest", "undoToast"] {
            XCTAssertFalse(mainListSource.contains("@Published var \(state)"))
            XCTAssertTrue(detailTagSource.contains("@Published var \(state)"))
        }
        for dependency in ["tagStore", "aiSettingsLoader", "aiTagSuggestionStore", "aiPrivacyRules",
                           "undoActionStore"] {
            XCTAssertTrue(detailTagSource.contains("let \(dependency):"))
        }
    }

    func testFileActionAndSyncConflictStateCannotReturnToMainListOwnership() throws {
        let mainListSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/MainList/MainFileListModel.swift"),
            encoding: .utf8
        )
        let fileActionSource = try String(
            contentsOf: productionDirectory()
                .appendingPathComponent("Features/FileActions/FileActionCoordinator.swift"),
            encoding: .utf8
        )
        let syncSource = try String(
            contentsOf: productionDirectory()
                .appendingPathComponent("Features/SyncConflicts/SyncConflictCoordinator.swift"),
            encoding: .utf8
        )

        for state in ["renameState", "deleteState", "changeCategoryState", "classifierCorrectionContextState"] {
            XCTAssertFalse(mainListSource.contains("@Published var \(state)"))
            XCTAssertTrue(fileActionSource.contains("@Published var \(state)"))
        }
        for dependency in ["fileRenamer", "fileDeleter", "fileCategoryMover", "categoryPredictor"] {
            XCTAssertFalse(mainListSource.contains("let \(dependency):"))
            XCTAssertTrue(fileActionSource.contains("let \(dependency):"))
        }
        XCTAssertFalse(mainListSource.contains("@Published var iCloudConflictResolutionState"))
        XCTAssertTrue(syncSource.contains("@Published var resolutionState"))

        let mainListSources = try productionSwiftFiles()
            .filter { $0.path.contains("/Features/MainList/") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for forbiddenFacade in [
            "func beginClassifierRuleHandoff(",
            "func loadMoveToCategoryPreview(",
            "func submitMoveToCategory(",
            "func submitAIClassificationSuggestion("
        ] {
            XCTAssertFalse(
                mainListSources.contains(forbiddenFacade),
                "MainList must not recreate the FileActionCoordinator facade: \(forbiddenFacade)"
            )
        }
    }

    func testFeatureCodeDoesNotAddPackageForwardingTypealiases() throws {
        XCTAssertEqual(
            try packageForwardingTypealiases(
                in: productionSwiftFiles(),
                productionDirectory: productionDirectory()
            ),
            [],
            "Feature consumers must import their owner Package instead of recreating App-global aliases."
        )
    }
}
