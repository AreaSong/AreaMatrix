@testable import AreaMatrix
import XCTest

final class SyncConflictReviewPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["C4-15"]

    func testS4X01DeclaresOnlyC415DetectBoundary() {
        XCTAssertEqual(Self.declaredCapabilities, ["C4-15"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.detectSyncConflicts))
        XCTAssertFalse(Self.declaredCapabilities.contains("C4-16"))
        XCTAssertFalse(Self.declaredCapabilities.contains("C4-21"))
    }

    @MainActor
    func testS4X01C415LoadUsesCoreBridgeDetectorAndSelectsRequestedConflict() async {
        let expected = SyncConflictSnapshot.s4x01Fixture(conflictID: "conflict-selected")
        let detector = S4X01RecordingSyncConflictDetector(result: .success([
            .s4x01Fixture(conflictID: "conflict-other"),
            expected
        ]))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictID: "conflict-selected",
            conflictDetector: detector,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.load()
        let requests = await detector.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/s4x01-repo"])
        XCTAssertEqual(model.state, .loaded(expected))
        XCTAssertEqual(model.conflict, expected)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testS4X01C415LoadedViewShowsSummaryAndVersionsWithoutResolutionActions() async throws {
        let conflict = SyncConflictSnapshot.s4x01Fixture()
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([conflict])),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.load()
        let loadedConflict = try XCTUnwrap(model.conflict)
        let body = s4x01MirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)

        XCTAssertEqual(loadedConflict.conflictType.displayName, "Same name, different content")
        XCTAssertEqual(loadedConflict.primaryPath, "docs/report.pdf")
        XCTAssertEqual(loadedConflict.affectedFiles.map(\.role.displayName), ["Existing file", "Incoming file"])
        XCTAssertEqual(loadedConflict.affectedFiles.map(\.path), [
            "docs/report.pdf",
            "docs/report (Windows conflict).pdf"
        ])
        XCTAssertTrue(body.contains(SyncConflictReviewAccessibilityID.page))
        XCTAssertTrue(body.contains(SyncConflictReviewCopy.title))
        XCTAssertFalse(body.contains("Apply resolution"))
        XCTAssertFalse(body.contains("Keep both"))
        XCTAssertFalse(body.contains("Use incoming version"))
        XCTAssertFalse(body.contains("S4-X-09"))
    }

    @MainActor
    func testS4X01C415FileDetailRouteSelectsConflictByAffectedPath() async {
        let expected = SyncConflictSnapshot.s4x01Fixture(conflictID: "conflict-matching-file")
        let detector = S4X01RecordingSyncConflictDetector(result: .success([
            .s4x01Fixture(conflictID: "conflict-other", primaryPath: "docs/other.pdf"),
            expected
        ]))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            primaryPath: "docs/report (Windows conflict).pdf",
            conflictDetector: detector,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.load()

        XCTAssertEqual(model.state, .loaded(expected))
    }

    @MainActor
    func testS4X01C415FileDetailEntryCanRouteToReviewSheet() async {
        let file = FileEntrySnapshot.s4x01Fixture(id: 141, path: "docs/report.pdf", currentName: "report.pdf")
        let opening = RepositoryOpeningResult.s4x01Fixture(repoPath: "/tmp/s4x01-repo", files: [file])
        var routedFile: FileEntrySnapshot?

        let model = MainFileListModel(
            opening: opening,
            fileLister: S4X01NoopFileLister(),
            fileDetailer: S4X01RecordingFileDetailer(result: .success(file)),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )
        await model.selectFiles([file.id])
        let body = s4x01MirrorDescription(of: MainRepositoryDetailPane(
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
            onBeginSyncConflictReview: { routedFile = $0 },
            onOpenAISettings: {},
            writeActionDisabledReason: model.writeActionDisabledReason,
            summaryExitController: AISummaryEditorExitController(),
            noteModel: DetailNoteModel(
                repoPath: opening.config.repoPath,
                noteStore: S4X01NoopNoteStore(),
                errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
            )
        ).body)
        let route = SyncConflictReviewRoute.fileDetail(repoPath: opening.config.repoPath, file: file)

        XCTAssertTrue(body.contains("Review Sync Conflict..."))
        XCTAssertTrue(body.contains("S4-X-01-C4-15-review-sync-conflict"))
        XCTAssertEqual(route, SyncConflictReviewRoute(
            repoPath: "/tmp/s4x01-repo",
            conflictID: nil,
            primaryPath: "docs/report.pdf"
        ))
        XCTAssertNil(routedFile)
    }

    @MainActor
    func testS4X01C415MissingOrResolvedConflictShowsEmptyState() async {
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictID: "missing-conflict",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([
                .s4x01Fixture(conflictID: "resolved-conflict", status: .resolved)
            ])),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.load()
        let body = s4x01MirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)

        XCTAssertEqual(model.state, .empty)
        XCTAssertTrue(body.contains(SyncConflictReviewCopy.emptyTitle))
        XCTAssertTrue(body.contains(SyncConflictReviewCopy.backAction))
        XCTAssertTrue(body.contains(SyncConflictReviewAccessibilityID.empty))
    }

    @MainActor
    func testS4X01C415ErrorStateMapsCoreErrorAndKeepsRetryVisible() async {
        let mapper = S4X01RecordingErrorMapper(mapping: .s4x01Mapping(
            kind: .conflict,
            rawContext: "stale conflict id"
        ))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .failure(CoreError.Conflict(
                path: "stale conflict id"
            ))),
            errorMapper: mapper
        )

        await model.load()
        let body = s4x01MirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "stale conflict id")])
        XCTAssertTrue(body.contains(SyncConflictReviewAccessibilityID.error))
        XCTAssertTrue(body.contains(SyncConflictReviewCopy.errorTitle))
        XCTAssertTrue(body.contains("Retry"))
    }
}

private actor S4X01RecordingSyncConflictDetector: CoreSyncConflictDetecting {
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

private actor S4X01RecordingErrorMapper: CoreErrorMapping {
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

private extension SyncConflictSnapshot {
    static func s4x01Fixture(
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
                .s4x01FileFixture(path: primaryPath, role: .existing),
                .s4x01FileFixture(
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

private extension RepositoryOpeningResult {
    static func s4x01Fixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
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

private extension FileEntrySnapshot {
    static func s4x01Fixture(id: Int64, path: String, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 2_048,
            hashSha256: "s4x01-file-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_778_738_300,
            updatedAt: 1_778_738_400
        )
    }
}

private extension SyncConflictAffectedFileSnapshot {
    static func s4x01FileFixture(
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
            sizeBytes: 2_048,
            modifiedAt: 1_778_738_400,
            hashSha256: hashSha256,
            sourcePlatform: sourcePlatform
        )
    }
}

private actor S4X01RecordingFileDetailer: CoreFileDetailing {
    private let result: Result<FileEntrySnapshot, Error>

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        try result.get()
    }
}

private struct S4X01NoopFileLister: CoreFileListing {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor S4X01NoopNoteStore: CoreNoteReadingWriting {
    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        nil
    }

    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws {}
}

private extension CoreErrorMappingSnapshot {
    static func s4x01Mapping(
        kind: CoreErrorKindSnapshot = .conflict,
        rawContext: String = "/tmp/s4x01-repo"
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

private func s4x01MirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS4X01MirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS4X01MirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS4X01MirrorDescription(of: child.value, to: &lines)
    }
}
