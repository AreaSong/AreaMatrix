@testable import AreaMatrix
import XCTest

final class GeneralSettingsImportDefaultModeTests: XCTestCase {
    @MainActor
    func testS126MoveDefaultFeedsLaterImportSheetDefaults() async throws {
        let opening = RepositoryOpeningResult.generalSettingsImportFixture(defaultMode: "Moved")
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: GeneralSettingsImportDefaultAnnouncer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.startImportEntry(opening: opening, source: .filePicker, urls: [sourceURL])
        let request = try XCTUnwrap(model.pendingImportEntry)

        XCTAssertEqual(request.defaultStorageMode, .move)
        try await assertSingleFileSheetUsesMove(request: request)
        assertBatchSheetUsesMove(opening: opening, sourceURL: sourceURL)
        await assertFolderSheetUsesMove(opening: opening)
    }

    @MainActor
    private func assertSingleFileSheetUsesMove(request: ImportEntryRequest) async throws {
        let singleModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        await singleModel.load(request: request)

        XCTAssertEqual(singleModel.selectedStorageMode, .move)
    }

    @MainActor
    private func assertBatchSheetUsesMove(opening: RepositoryOpeningResult, sourceURL: URL) {
        let batchModel = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )
        batchModel.applyPreviewRows(
            [
                ImportBatchPreviewRow.ready(url: sourceURL, prediction: .s117Fixture())
            ],
            request: ImportEntryRequest(
                repoPath: opening.config.repoPath,
                source: .dropZone,
                destination: .autoClassify,
                urls: [sourceURL, URL(fileURLWithPath: "/tmp/other.pdf")],
                kind: .multipleItems(2),
                defaultStorageMode: .move
            ),
            selectedDestination: .autoClassify
        )

        XCTAssertEqual(batchModel.selectedStorageMode, .move)
    }

    @MainActor
    private func assertFolderSheetUsesMove(opening: RepositoryOpeningResult) async {
        let folderModel = ImportFolderPreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S118RecordingBatchImporter(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: S119StaticFolderScanner(result: ImportFolderScanResult(
                rows: [],
                folderCount: 0,
                skippedRules: [],
                errors: []
            ))
        )

        await folderModel.load(request: ImportEntryRequest(
            repoPath: opening.config.repoPath,
            source: .dropZone,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/import-folder", isDirectory: true)],
            kind: .folder,
            defaultStorageMode: .move
        ))

        XCTAssertEqual(folderModel.selectedStorageMode, .move)
    }
}

@MainActor
private final class GeneralSettingsImportDefaultAnnouncer: AccessibilityAnnouncing {
    func announce(_: String) {}
}

private actor GeneralSettingsImportDefaultErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "保存失败",
            severity: .medium,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "S1-26 import default"
        )
    }
}

private extension RepositoryOpeningResult {
    static func generalSettingsImportFixture(defaultMode: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: "/tmp/repo",
                defaultMode: defaultMode,
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "system",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: 0,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}
