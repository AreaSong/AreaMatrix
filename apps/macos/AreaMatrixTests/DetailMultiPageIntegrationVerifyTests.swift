import XCTest
@testable import AreaMatrix

final class DetailMultiPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS115PageIntegrationUsesRealC111AndC112CoreBridgeForMultiSelection() async throws {
        let repoURL = try makeS115TemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "contract".write(to: docsURL.appendingPathComponent("contract.pdf"), atomically: true, encoding: .utf8)
        try "notes".write(to: docsURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let config = try await bridge.loadConfig(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        let model = MainFileListModel(
            opening: RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: []),
            fileLister: bridge,
            fileDetailer: bridge,
            errorMapper: bridge
        )

        await model.loadCurrentCategory("docs")
        let selectedIDs = Set(model.files.map(\.id))
        await model.selectFiles(selectedIDs)
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        XCTAssertEqual(selectedIDs.count, 2)
        XCTAssertEqual(model.selection, .multiple(selectedIDs))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.selectedFileNoteWriteBlock)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.detailLogState, .notLoaded)
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.unresolvedMetadataCount, 0)
        XCTAssertFalse(summary.warningMessages.contains("部分选中项无法读取元数据"))
        XCTAssertEqual(summary.fileTypeRows.map(\.label).sorted(), ["Markdown", "PDF"])
    }

    @MainActor
    func testS115PageIntegrationExitsToSingleAndEmptyWithoutBatchWriteActions() async {
        let first = FileEntrySnapshot.s115Fixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.s115Fixture(id: 2, currentName: "b.pdf")
        let detailer = S115SequenceDetailer(results: [
            .success(first),
            .success(second),
            .success(second),
        ])
        let model = MainFileListModel(
            opening: .s115Fixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: S115NoopLister(),
            fileDetailer: detailer,
            errorMapper: S115ErrorMapper(mapping: .s115DbMapping())
        )

        await model.selectFiles([first.id, second.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginDelete()

        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.selectedFileNoteWriteBlock)
        XCTAssertEqual(model.detailLogState, .notLoaded)

        await model.selectFiles([second.id])
        XCTAssertEqual(model.selection, .single(second.id))
        XCTAssertEqual(model.selectedFileDetail, second)

        await model.selectFiles([])
        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testS115PageIntegrationKeepsCopyPathsAvailableOnPartialC112Failure() async {
        let available = FileEntrySnapshot.s115Fixture(id: 10, currentName: "available.pdf")
        let stale = FileEntrySnapshot.s115Fixture(id: 11, currentName: "stale.pdf")
        let mapping = CoreErrorMappingSnapshot.s115FileNotFoundMapping()
        let model = MainFileListModel(
            opening: .s115Fixture(repoPath: "/tmp/repo", files: [available, stale]),
            fileLister: S115NoopLister(),
            fileDetailer: S115SequenceDetailer(results: [
                .success(available),
                .failure(CoreError.FileNotFound(path: stale.path)),
            ]),
            errorMapper: S115ErrorMapper(mapping: mapping)
        )

        await model.selectFiles([available.id, stale.id])
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)
        let copier = ShellRecordingPathCopier()
        let announcer = S117RecordingAccessibilityAnnouncer()
        let shell = OnboardingModel(
            pathCopier: copier,
            accessibilityAnnouncer: announcer
        )
        shell.copyMainListPaths(
            opening: .s115Fixture(repoPath: "/tmp/repo", files: model.files),
            relativePaths: summary.paths
        )

        XCTAssertEqual(model.selection, .multiple([available.id, stale.id]))
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(summary.paths, [available.path, stale.path])
        XCTAssertEqual(copier.multiPathRequests.map(\.relativePaths), [[available.path, stale.path]])
        XCTAssertEqual(shell.toastMessage, "2 paths copied.")
        XCTAssertEqual(announcer.announcements, ["2 paths copied."])
    }
}

private actor S115NoopLister: CoreFileListing {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor S115SequenceDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }
}

private actor S115ErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private extension RepositoryOpeningResult {
    static func s115Fixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .s115Fixture(repoPath: repoPath),
            tree: .s115TreeFixture(fileCount: Int64(files.count)),
            currentCategoryFiles: files
        )
    }
}

private extension RepoConfigSnapshot {
    static func s115Fixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
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
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func s115TreeFixture(fileCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            fileCount: fileCount,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: fileCount, children: []),
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func s115Fixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "s115-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func s115DbMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "S1-15 C1-11 list_files"
        )
    }

    static func s115FileNotFoundMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "部分选中项无法读取元数据",
            severity: .medium,
            suggestedAction: "刷新当前选择，确认文件是否仍在资料库中。",
            recoverability: .refreshRequired,
            rawContext: "S1-15 C1-12 get_file"
        )
    }
}

private func makeS115TemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS115Integration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
