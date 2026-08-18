import Foundation
import XCTest

final class MacOSArchitectureBoundaryGovernanceTests: MacOSGovernanceTestCase {
    func testFeatureRoutingStateCannotReturnToMainRepositoryContentView() throws {
        let contentViewSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentView.swift"),
            encoding: .utf8
        )
        let owners = [
            ("Features/Search/SearchModel.swift", "@Published var routingState = MainRepositorySearchRoutingState()"),
            ("Features/Search/SearchModel.swift", "@Published var savedSearchesBySidebarID"),
            (
                "Features/FileActions/FileActionCoordinator.swift",
                "@Published var routingState = MainFileActionRoutingState()"
            ),
            ("Features/SyncConflicts/SyncConflictCoordinator.swift", "@Published var reviewRoutingState"),
            ("Features/CommandPalette/CommandPaletteState.swift", "@Published var focusRoutingState"),
            ("Features/CommandPalette/CommandPaletteState.swift", "@Published var importConflictBatchRelayState")
        ]

        for (path, declaration) in owners {
            let source = try String(
                contentsOf: productionDirectory().appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains(declaration), "Missing Feature-owned route state: \(declaration)")
        }
        for forbidden in [
            "@State var fileActionRoutingState",
            "@State var importConflictBatchRelayState",
            "@State var commandPaletteFocusRoutingState",
            "@State var searchRoutingState",
            "@State var savedSearchesBySidebarID",
            "@State var smartListLoadError",
            "@State var syncConflictReviewRoutingState"
        ] {
            XCTAssertFalse(contentViewSource.contains(forbidden), "Route state returned to content View: \(forbidden)")
        }
    }

    func testSelectionAndSummaryExitStateStayWithTheirOwners() throws {
        let contentViewSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Views/Main/MainRepositoryContentView.swift"),
            encoding: .utf8
        )
        let selectionSource = try String(
            contentsOf: testsDirectory().deletingLastPathComponent().appendingPathComponent(
                "Packages/AreaMatrixModules/Sources/AreaMatrixFeatureLibrary/LibrarySelectionModel.swift"
            ),
            encoding: .utf8
        )
        let summarySource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Features/AI/AISummaryEditorSupport.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contentViewSource.contains("@StateObject var selectionModel: MainSelectionModel"))
        XCTAssertFalse(contentViewSource.contains("@State var selectedFileIDs"))
        XCTAssertFalse(contentViewSource.contains("@State var pendingMovedFileFocusID"))
        XCTAssertFalse(contentViewSource.contains("@State var summarySelectionExitState"))
        XCTAssertTrue(selectionSource.contains("public final class MainSelectionModel: ObservableObject"))
        XCTAssertTrue(summarySource.contains("@Published var selectionExitState = AISummarySelectionExitState()"))
    }

    func testSyncConflictSheetStaysWithItsFeatureHost() throws {
        let source = try String(
            contentsOf: productionDirectory()
                .appendingPathComponent("Features/SyncConflicts/SyncConflictReviewSupportViews.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("struct SyncConflictReviewHostModifier: ViewModifier"))
        XCTAssertFalse(source.contains("extension MainRepositoryContentView"))
    }

    func testProductionCodeDoesNotAddMutableStaticStoredState() throws {
        let expression = try NSRegularExpression(
            pattern: #"(?m)\bstatic\s+var\s+([A-Za-z_][A-Za-z0-9_]*)[^\n{]*="#
        )
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0) != "Bridge/UniFFI/area_matrix.swift" }
            .flatMap { file -> [String] in
                let source = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(source.startIndex ..< source.endIndex, in: source)
                return expression.matches(in: source, range: range).compactMap { match in
                    guard let nameRange = Range(match.range(at: 1), in: source) else { return nil }
                    return "\(relativeProductionPath(for: file)):\(source[nameRange])"
                }
            }

        XCTAssertEqual(
            violations,
            [],
            "Mutable process-wide storage must have an explicit actor/runtime owner; computed adapters are allowed."
        )
    }

    func testRepositorySessionRemainsOwnedByIngestionPackage() throws {
        let appSession = productionDirectory()
            .appendingPathComponent("Features/RepositoryLifecycle/RepositorySession.swift")
        let packageSession = testsDirectory().deletingLastPathComponent().appendingPathComponent(
            "Packages/AreaMatrixModules/Sources/AreaMatrixFeatureIngestion/RepositorySessionContracts.swift"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: appSession.path))
        let source = try String(contentsOf: packageSession, encoding: .utf8)
        XCTAssertTrue(source.contains("public final class RepositorySession"))
        XCTAssertTrue(source.contains("public func makeOperationContext() -> RepositoryOperationContext"))
        XCTAssertTrue(source.contains("case repositoryIdentityMismatch"))
    }

    func testRemoteProviderContractsCannotReturnToAppFeatureOwnership() throws {
        let featureSources = try productionSwiftFiles()
            .filter { $0.path.contains("/Features/") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for type in [
            "AISettingsFeatureKind", "RemoteProviderKindState", "RemoteProviderTestRequestState",
            "RemoteProviderEnableRequestState", "RemoteProviderConfigState", "RemoteProviderTestResultState",
            "RemotePrivacyGateAction", "RemoteProviderConfigDraft", "RemoteProviderDraftFingerprint"
        ] {
            let pattern = #"(?m)^(?:public\s+|internal\s+|private\s+|fileprivate\s+)?(?:struct|enum|class)\s+"# +
                NSRegularExpression.escapedPattern(for: type) + #"\b"#
            let declaration = try NSRegularExpression(pattern: pattern)
            let range = NSRange(featureSources.startIndex ..< featureSources.endIndex, in: featureSources)
            XCTAssertEqual(declaration.numberOfMatches(in: featureSources, range: range), 0, "\(type) returned to App.")
        }
    }

    func testBatchRenameContractsCannotReturnToAppFeatureOwnership() throws {
        let featureSources = try productionSwiftFiles()
            .filter { $0.path.contains("/Features/") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for type in [
            "BatchRenameModeSnapshot", "BatchRenameDateSourceSnapshot", "BatchRenameRuleSnapshot",
            "BatchRenamePreviewStatusSnapshot", "BatchRenamePreviewItemSnapshot",
            "BatchRenamePreviewReportSnapshot", "BatchRenameResultStatusSnapshot",
            "BatchRenameItemResultSnapshot"
        ] {
            let pattern = #"(?m)^(?:public\s+|internal\s+|private\s+|fileprivate\s+)?(?:struct|enum|class)\s+"# +
                NSRegularExpression.escapedPattern(for: type) + #"\b"#
            let declaration = try NSRegularExpression(pattern: pattern)
            let range = NSRange(featureSources.startIndex ..< featureSources.endIndex, in: featureSources)
            XCTAssertEqual(declaration.numberOfMatches(in: featureSources, range: range), 0, "\(type) returned to App.")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: productionDirectory()
                    .appendingPathComponent("Features/FileActions/BatchRenameSnapshots.swift").path
            )
        )
    }

    func testStartupRecoveryContractsCannotReturnToAppFeatureOwnership() throws {
        let featureSources = try productionSwiftFiles()
            .filter { $0.path.contains("/Features/") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for declaration in [
            "protocol CoreStartupRecovering",
            "struct RecoveryReportSnapshot",
            "struct RepositoryInitializationResult"
        ] {
            XCTAssertFalse(featureSources.contains(declaration), "\(declaration) returned to App Feature ownership.")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: productionDirectory()
                    .appendingPathComponent("Features/Onboarding/StartupRecoveryModels.swift").path
            )
        )
    }

    func testCoreVersionContractsCannotReturnToAppFeatureOwnership() throws {
        let featureSources = try productionSwiftFiles()
            .filter { $0.path.contains("/Features/") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for declaration in ["protocol CoreVersionReading", "protocol CoreVersionLoading"] {
            XCTAssertFalse(featureSources.contains(declaration), "\(declaration) returned to App Feature ownership.")
        }
    }
}
