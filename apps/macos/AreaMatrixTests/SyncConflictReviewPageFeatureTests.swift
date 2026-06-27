@testable import AreaMatrix
import XCTest

final class SyncConflictReviewPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = [
        "sync-conflict-detect",
        "sync-conflict-resolve",
        "replace-confirmation"
    ]

    func testSyncConflictReviewDeclaresOnlyDetectResolveAndReplaceConfirmBoundaries() {
        XCTAssertEqual(
            Self.declaredCapabilities,
            ["sync-conflict-detect", "sync-conflict-resolve", "replace-confirmation"]
        )
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.detectSyncConflicts))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.previewSyncConflictResolution))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.resolveSyncConflict))
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreLoadUsesCoreBridgeDetectorAndSelectsRequestedConflict() async {
        let expected = SyncConflictSnapshot.syncConflictReviewFixture(conflictID: "conflict-selected")
        let detector = SyncConflictReviewDetector(result: .success([
            .syncConflictReviewFixture(conflictID: "conflict-other"),
            expected
        ]))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictID: "conflict-selected",
            conflictDetector: detector,
            conflictResolver: SyncConflictReviewResolver(previewResults: [
                .keepBoth: .success(.syncConflictReviewPreviewFixture(conflictID: "conflict-selected"))
            ]),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()
        let requests = await detector.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/syncConflictReview-repo"])
        XCTAssertEqual(model.state, .loaded(expected))
        XCTAssertEqual(model.conflict, expected)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreFileDetailRouteSelectsConflictByAffectedPath() async {
        let expected = SyncConflictSnapshot.syncConflictReviewFixture(conflictID: "conflict-matching-file")
        let detector = SyncConflictReviewDetector(result: .success([
            .syncConflictReviewFixture(conflictID: "conflict-other", primaryPath: "docs/other.pdf"),
            expected
        ]))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            primaryPath: "docs/report (Windows conflict).pdf",
            conflictDetector: detector,
            conflictResolver: SyncConflictReviewResolver(previewResults: [
                .keepBoth: .success(.syncConflictReviewPreviewFixture(conflictID: "conflict-matching-file"))
            ]),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()

        XCTAssertEqual(model.state, .loaded(expected))
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreFileDetailEntryCanRouteToReviewSheet() async {
        let file = FileEntrySnapshot.syncConflictReviewFixture(
            id: 141,
            path: "docs/report.pdf",
            currentName: "report.pdf"
        )
        let opening = RepositoryOpeningResult.syncConflictReviewFixture(
            repoPath: "/tmp/syncConflictReview-repo",
            files: [file]
        )
        var routedFile: FileEntrySnapshot?

        let model = MainFileListModel(
            opening: opening,
            fileLister: SyncConflictReviewNoopFileLister(),
            fileDetailer: SyncConflictReviewRecordingFileDetailer(result: .success(file)),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )
        await model.selectFiles([file.id])
        let detailPane = makeSyncConflictReviewDetailPane(
            model: model,
            opening: opening,
            onBeginSyncConflictReview: { routedFile = $0 }
        )
        let body = syncConflictReviewMirrorDescription(of: detailPane.body)
        let route = SyncConflictReviewRoute.fileDetail(repoPath: opening.config.repoPath, file: file)

        assertTestDescription(body, contains: [
            "Review Sync Conflict...",
            "sync-conflict-review-sync-conflict-detect-review-sync-conflict"
        ])
        XCTAssertEqual(route, SyncConflictReviewRoute(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictID: nil,
            primaryPath: "docs/report.pdf"
        ))
        XCTAssertNil(routedFile)
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreMissingOrResolvedConflictShowsEmptyState() async {
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictID: "missing-conflict",
            conflictDetector: SyncConflictReviewDetector(result: .success([
                .syncConflictReviewFixture(conflictID: "resolved-conflict", status: .resolved)
            ])),
            conflictResolver: SyncConflictReviewResolver(previewResults: [:]),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()
        let body = syncConflictReviewMirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)

        XCTAssertEqual(model.state, .empty)
        assertTestDescription(body, contains: [
            SyncConflictReviewCopy.emptyTitle,
            SyncConflictReviewCopy.backAction,
            SyncConflictReviewAccessibilityID.empty
        ])
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreErrorStateMapsCoreErrorAndKeepsRetryVisible() async {
        let mapper = SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping(
            kind: .conflict,
            rawContext: "stale conflict id"
        ))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictDetector: SyncConflictReviewDetector(result: .failure(CoreError.Conflict(
                path: "stale conflict id"
            ))),
            conflictResolver: SyncConflictReviewResolver(previewResults: [:]),
            errorMapper: mapper
        )

        await model.load()
        let body = syncConflictReviewMirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "stale conflict id")])
        assertTestDescription(body, contains: [
            SyncConflictReviewAccessibilityID.error,
            SyncConflictReviewCopy.errorTitle,
            "Retry"
        ])
    }
}

@MainActor
private func makeSyncConflictReviewDetailPane(
    model: MainFileListModel,
    opening: RepositoryOpeningResult,
    onBeginSyncConflictReview: @escaping (FileEntrySnapshot) -> Void
) -> MainRepositoryDetailPane {
    MainRepositoryDetailPane(
        selection: model.selection,
        multiSelectionSummary: MultiSelectionDetailSummary(selection: model.selection, files: model.files),
        detailErrorMapping: model.detailErrorMapping,
        isDetailLoading: model.isDetailLoading,
        selectedFileDetail: model.selectedFileDetail,
        noteWriteBlock: model.selectedFileNoteWriteBlock,
        detailLogState: model.detailLogState,
        detailLogDiagnosticsState: model.detailLogDiagnosticsState,
        detailExternalCreateSyncState: model.detailExternalCreateSyncState,
        detailTagEditorState: model.detailTagEditorState,
        detailTagSuggestionState: model.detailTagSuggestionState,
        tagSuggestionPresentationRequest: model.tagSuggestionPresentationRequest,
        detailTagUndoToast: model.detailTagUndoToast,
        detailTabRequest: model.detailTabRequest,
        selectedImportProgressRow: nil,
        semanticDetail: nil,
        repoPath: opening.config.repoPath,
        batchTagStore: CoreBridge(),
        batchTagUndoStore: CoreBridge(),
        batchTagErrorMapper: model.errorMapper,
        batchDeleter: CoreBridge(),
        batchCategoryChanger: CoreBridge(),
        batchRenamer: CoreBridge(),
        categoryRows: opening.tree.sidebarRows,
        onBatchCategoryApplied: { _ in },
        onBatchDeleteApplied: { _ in },
        onBatchRenameApplied: { _ in },
        onBatchCategoryCreateNewCategory: { _ in },
        onRetrySelectedFileDetail: {},
        tagActions: .noop,
        onCopyPaths: { _ in },
        onOpenNoteFile: { _ in },
        onRefreshChangeLog: {},
        onRequestDetailLogDiagnostics: {},
        onConfirmDetailLogDiagnostics: {},
        onCancelDetailLogDiagnostics: {},
        onDetailTabRequestConsumed: { _ in },
        onBeginRenameFile: { _ in },
        onBeginChangeCategoryFile: { _ in },
        onBeginClassifierCorrectionFile: { _ in },
        onBeginAIClassificationSuggestionFile: { _ in },
        onBeginDeleteFile: { _ in },
        onBeginICloudConflictResolution: { _ in },
        onBeginSyncConflictReview: onBeginSyncConflictReview,
        onOpenAISettings: {},
        writeActionDisabledReason: model.writeActionDisabledReason,
        summaryExitController: AISummaryEditorExitController(),
        noteModel: makeSyncConflictReviewDetailNoteModel(repoPath: opening.config.repoPath)
    )
}

@MainActor
private func makeSyncConflictReviewDetailNoteModel(repoPath: String) -> DetailNoteModel {
    DetailNoteModel(
        repoPath: repoPath,
        noteStore: SyncConflictReviewNoopNoteStore(),
        errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
    )
}

actor SyncConflictReviewDetector: CoreSyncConflictDetecting {
    private let result: Result<[SyncConflictSnapshot], Error>
    private var requests: [String] = []

    init(result: Result<[SyncConflictSnapshot], Error>) {
        self.result = result
    }

    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictSnapshot] {
        requests.append(repoPath)
        return try result.get()
    }

    func recordedRequests() -> [String] {
        requests
    }
}

actor SyncConflictReviewRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

extension SyncConflictSnapshot {
    static func syncConflictReviewFixture(
        conflictID: String = "conflict-report",
        status: SyncConflictStatusSnapshot = .needsReview,
        primaryPath: String = "docs/report.pdf"
    ) -> SyncConflictSnapshot {
        SyncConflictSnapshot(
            conflictID: conflictID,
            conflictType: .sameNameDifferentContent,
            severity: .high,
            status: status,
            primaryPath: primaryPath,
            affectedFiles: [
                .syncConflictReviewFileFixture(path: primaryPath, role: .existing),
                .syncConflictReviewFileFixture(
                    path: primaryPath == "docs/report.pdf"
                        ? "docs/report (Windows conflict).pdf"
                        : "docs/other (Windows conflict).pdf",
                    fileID: 43,
                    role: .incoming,
                    hashSha256: "fedcba9876543210",
                    sourcePlatform: "Windows"
                )
            ],
            versionCount: 2,
            sourceProvider: "OneDrive",
            detectedAt: 1_778_738_400,
            summary: "Two versions of docs/report.pdf need review."
        )
    }
}

extension RepositoryOpeningResult {
    static func syncConflictReviewFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "Repository",
                kind: "RepositoryRoot",
                relativePath: "",
                fileCount: Int64(files.count),
                depth: 0,
                children: []
            ),
            currentCategoryFiles: files
        )
    }
}

extension FileEntrySnapshot {
    static func syncConflictReviewFixture(id: Int64, path: String, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 2048,
            hashSha256: "syncConflictReview-file-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_778_738_300,
            updatedAt: 1_778_738_400
        )
    }
}

extension SyncConflictAffectedFileSnapshot {
    static func syncConflictReviewFileFixture(
        path: String = "docs/report.pdf",
        fileID: Int64? = 42,
        role: SyncConflictFileRoleSnapshot = .existing,
        hashSha256: String? = "abcdef1234567890",
        sourcePlatform: String? = "macOS"
    ) -> SyncConflictAffectedFileSnapshot {
        SyncConflictAffectedFileSnapshot(
            path: path,
            fileID: fileID,
            role: role,
            sizeBytes: 2048,
            modifiedAt: 1_778_738_400,
            hashSha256: hashSha256,
            sourcePlatform: sourcePlatform
        )
    }
}

actor SyncConflictReviewRecordingFileDetailer: CoreFileDetailing {
    private let result: Result<FileEntrySnapshot, Error>

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        try result.get()
    }
}

struct SyncConflictReviewNoopFileLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

actor SyncConflictReviewNoopNoteStore: CoreNoteReadingWriting {
    func readNote(repoPath _: String, fileID _: Int64) async throws -> String? {
        nil
    }

    func writeNote(repoPath _: String, fileID _: Int64, contentMarkdown _: String) async throws {}
}

extension CoreErrorMappingSnapshot {
    static func syncConflictReviewMapping(
        kind: CoreErrorKindSnapshot = .conflict,
        rawContext: String = "/tmp/syncConflictReview-repo"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this sync conflict.",
            severity: .high,
            suggestedAction: "Refresh the conflict list or retry after sync finishes.",
            recoverability: .refreshRequired,
            rawContext: rawContext
        )
    }
}

func syncConflictReviewMirrorDescription(of value: Any) -> String {
    testMirrorDescription(of: value)
}
