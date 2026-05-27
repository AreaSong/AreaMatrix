@testable import AreaMatrix
import XCTest

private struct DetailIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let bridge: CoreBridge
    let model: MainFileListModel
    let primary: FileEntrySnapshot
    let secondary: FileEntrySnapshot
}

// swiftlint:disable:next type_body_length
final class DetailIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS112ToS115DetailLoopUsesRealCoreBridgeWithoutFinalMock() async throws {
        let context = try await makeDetailIntegrationContext()
        defer {
            try? FileManager.default.removeItem(at: context.repoURL)
            try? FileManager.default.removeItem(at: context.sourceRootURL)
        }

        try await verifySingleFileMetaAndInitialLog(context)
        try await verifyDetailNoteRoundTrip(
            bridge: context.bridge,
            repoURL: context.repoURL,
            file: XCTUnwrap(context.model.selectedFileDetail)
        )
        try await verifyTagCrudRoundTrip(context)
        try await verifyExternalSyncEvents(context)
        await verifyMultiSelectionSummary(context)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testS208PageIntegrationVerifyConnectsEntryExitErrorsAndDeclaredCoreOnly() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 219, currentName: "integration.pdf")
        let filters = SearchFilterEditing.settingTagMatchMode(
            .all,
            in: SearchFilterEditing.togglingTag(
                "tax",
                in: SearchFilterEditing.togglingTag("finance", in: .empty)
            )
        )
        let tagStore = DetailTagRecordingStore(
            listResults: [
                .success(.s208RegistryFixture(fileID: detail.id)),
                .failure(CoreError.Db(message: "tags")),
                .success(.s208RegistryFixture(fileID: detail.id))
            ]
        )
        let facets = MainListRecordingSearchFiltering(results: [
            .success(.s208IntegrationFacets()),
            .failure(CoreError.Db(message: "counts")),
            .success(.s208IntegrationFacets())
        ])
        let searcher = MainListRecordingSearchQuerying(results: [.success(.s208IntegrationSearchPage(filters))])
        let mapper = DetailMetaErrorMapper(mapping: .s208FilterFailure())
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            searchQuerying: searcher,
            searchFiltering: facets,
            tagStore: tagStore,
            errorMapper: mapper
        )

        await model.selectFiles([detail.id])
        await model.runSearch(
            query: "",
            scope: .all,
            sort: .newestImported,
            sidebarRow: .s208IntegrationRoot,
            filters: filters
        )
        await model.loadSearchFacets(query: "", scope: .all, sidebarRow: .s208IntegrationRoot, filters: filters)
        await model.loadTagFilterRegistry(activeFileID: detail.id)
        model.beginSmartListFilterDraft(id: 42, name: "Tagged", filters: .empty)
        model.updateSmartListFilterDraft(filters)
        await model.loadSearchFacets(query: "", scope: .all, sidebarRow: .s208IntegrationRoot, filters: filters)
        await model.retrySearchFacets()
        await model.retryTagFilterRegistry()

        let searchRequests = await searcher.recordedRequests().map(\.request)
        let facetRequests = await facets.recordedRequests().map(\.request)
        XCTAssertEqual(searchRequests.map(\.filters.tags), [filters.tags])
        XCTAssertEqual(searchRequests.map(\.filters.tagMatchMode), [.all])
        XCTAssertEqual(facetRequests.map(\.filters.tags), [filters.tags, filters.tags, filters.tags])
        XCTAssertEqual(facetRequests.map(\.filters.tagMatchMode), [.all, .all, .all])
        XCTAssertEqual(model.tagFilterRegistryState.errorMapping, .s208FilterFailure())
        XCTAssertEqual(model.tagFilterRegistryState.tagSet?.availableTags.map(\.value), ["finance", "legal"])
        XCTAssertEqual(model.searchFacetsState.facets?.tags.map(\.value), ["finance", "tax", "archive"])
        await model.retryTagFilterRegistry()
        XCTAssertNil(model.tagFilterRegistryState.errorMapping)
        XCTAssertEqual(model.smartListFilterDraft?.filters, filters)
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 42, name: "Tagged"))
        let tagListRequestFileIDs = await tagStore.listRequests().map(\.fileID)
        let tagAddRequests = await tagStore.addRequests()
        let tagRemoveRequests = await tagStore.removeRequests()
        XCTAssertEqual(tagListRequestFileIDs, [detail.id, detail.id, detail.id])
        XCTAssertEqual(tagAddRequests, [])
        XCTAssertEqual(tagRemoveRequests, [])
    }

    @MainActor
    func testS208SidebarTagsEntryOpensSameTagFilterRouteWithoutMutatingTags() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 220, currentName: "sidebar-tags.pdf")
        let tagStore = DetailTagRecordingStore(listResults: [.success(.s208RegistryFixture(fileID: detail.id))])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            searchQuerying: MainListRecordingSearchQuerying(results: [.success(.s208IntegrationSearchPage(.empty))]),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.s208IntegrationFacets())]),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s208FilterFailure())
        )

        model.enterSearch(context: .sidebar("S2-08-sidebar-tags-filter"))
        await model.loadTagFilterRegistry(activeFileID: detail.id)

        XCTAssertEqual(
            model.lastSearchExitContext,
            .sidebar("S2-08-sidebar-tags-filter")
        )
        let tagListRequests = await tagStore.listRequests()
        let tagAddRequests = await tagStore.addRequests()
        let tagRemoveRequests = await tagStore.removeRequests()

        XCTAssertEqual(tagListRequests, [
            DetailTagListRequest(repoPath: "/tmp/repo", fileID: detail.id)
        ])
        XCTAssertEqual(tagAddRequests, [])
        XCTAssertEqual(tagRemoveRequests, [])
    }

    @MainActor
    private func makeDetailIntegrationContext() async throws -> DetailIntegrationContext {
        let repoURL = try makeDetailIntegrationTemporaryRepositoryURL()
        let sourceRootURL = try makeDetailIntegrationTemporaryRepositoryURL()
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let primary = try await importDetailFixture(
            bridge: bridge,
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            filename: "contract.pdf",
            content: "primary"
        )
        let secondary = try await importDetailFixture(
            bridge: bridge,
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            filename: "notes.md",
            content: "secondary"
        )

        let model = try await makeDetailIntegrationModel(bridge: bridge, repoURL: repoURL)
        return DetailIntegrationContext(
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            bridge: bridge,
            model: model,
            primary: primary,
            secondary: secondary
        )
    }

    @MainActor
    private func verifySingleFileMetaAndInitialLog(_ context: DetailIntegrationContext) async throws {
        await context.model.loadCurrentCategory("docs")
        await context.model.selectFiles([context.primary.id])
        XCTAssertEqual(context.model.selectedFileDetail?.id, context.primary.id)
        XCTAssertEqual(
            try detailMetaMetadataRows(for: XCTUnwrap(context.model.selectedFileDetail)).value(for: "Status"),
            "OK"
        )

        await context.model.loadSelectedFileChangeLog()
        assertLoadedLog(context.model.detailLogState, fileID: context.primary.id, expectedAction: "imported")
    }

    @MainActor
    private func verifyDetailNoteRoundTrip(
        bridge: CoreBridge,
        repoURL: URL,
        file: FileEntrySnapshot
    ) async throws {
        let noteModel = DetailNoteModel(
            repoPath: repoURL.path,
            noteStore: bridge,
            errorMapper: bridge,
            debounceNanoseconds: 1
        )
        await noteModel.load(file: file, writeBlock: nil)
        noteModel.createNote()
        noteModel.updateDraft("# Detail note")
        await waitForDetailIntegrationNoteSave(noteModel)

        let note = try await bridge.readNote(repoPath: repoURL.path, fileID: file.id)

        XCTAssertEqual(note, "# Detail note")
        XCTAssertEqual(noteModel.state, .editing(
            fileID: file.id,
            content: "# Detail note",
            saveStatus: .saved,
            writeBlock: nil
        ))
    }

    @MainActor
    private func verifyTagCrudRoundTrip(_ context: DetailIntegrationContext) async throws {
        let file = try XCTUnwrap(context.model.selectedFileDetail)
        let originalCategory = file.category
        let originalPath = file.path

        await context.model.loadSelectedFileTags()
        assertLoadedTags(context.model.detailTagEditorState, fileID: file.id, expectedValues: [])

        await context.model.addSelectedFileTag(" ClientA ")
        assertLoadedTags(context.model.detailTagEditorState, fileID: file.id, expectedValues: ["clienta"])
        XCTAssertEqual(context.model.detailTagUndoToast?.message, #"Added tag "clienta"."#)

        let addedTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(addedTags.fileTags.map(\.value), ["clienta"])

        await context.model.undoLastDetailTagChange()
        assertLoadedTags(context.model.detailTagEditorState, fileID: file.id, expectedValues: [])
        XCTAssertNil(context.model.detailTagUndoToast)
        let undoneAddedTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(undoneAddedTags.fileTags, [])

        await context.model.addSelectedFileTag("clienta")
        assertLoadedTags(context.model.detailTagEditorState, fileID: file.id, expectedValues: ["clienta"])

        await context.model.removeSelectedFileTag("clienta")
        assertLoadedTags(context.model.detailTagEditorState, fileID: file.id, expectedValues: [])
        XCTAssertEqual(context.model.detailTagUndoToast?.message, #"Removed tag "clienta"."#)

        let removedTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(removedTags.fileTags, [])

        await context.model.undoLastDetailTagChange()
        assertLoadedTags(context.model.detailTagEditorState, fileID: file.id, expectedValues: ["clienta"])
        XCTAssertNil(context.model.detailTagUndoToast)
        let restoredTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(restoredTags.fileTags.map(\.value), ["clienta"])
        XCTAssertEqual(context.model.selectedFileDetail?.category, originalCategory)
        XCTAssertEqual(context.model.selectedFileDetail?.path, originalPath)
    }

    @MainActor
    private func verifyExternalSyncEvents(_ context: DetailIntegrationContext) async throws {
        let externalURL = context.repoURL.appendingPathComponent("docs/external.txt")
        let renamedURL = context.repoURL.appendingPathComponent("docs/external-renamed.txt")

        try "external".write(to: externalURL, atomically: true, encoding: .utf8)
        try await syncAndAssertDetailLog(
            model: context.model,
            kind: .created,
            relativePath: "docs/external.txt",
            fsEventID: 23001,
            expectedAction: "external_modified"
        )

        try FileManager.default.moveItem(at: externalURL, to: renamedURL)
        try await syncAndAssertDetailLog(
            model: context.model,
            kind: .renamed,
            relativePath: "docs/external-renamed.txt",
            fsEventID: 23002,
            expectedAction: "renamed"
        )

        try FileManager.default.removeItem(at: renamedURL)
        try await syncAndAssertDetailLog(
            model: context.model,
            kind: .removed,
            relativePath: "docs/external-renamed.txt",
            fsEventID: 23003,
            expectedAction: "deleted"
        )
    }

    @MainActor
    private func verifyMultiSelectionSummary(_ context: DetailIntegrationContext) async {
        await context.model.selectFiles([context.primary.id, context.secondary.id])
        let summary = MultiSelectionDetailSummary(selection: context.model.selection, files: context.model.files)

        XCTAssertEqual(context.model.selection, .multiple([context.primary.id, context.secondary.id]))
        XCTAssertNil(context.model.selectedFileDetail)
        XCTAssertNil(context.model.selectedFileNoteWriteBlock)
        XCTAssertNil(context.model.pendingActionDestination)
        XCTAssertEqual(context.model.detailLogState, .notLoaded)
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.unresolvedMetadataCount, 0)
        XCTAssertEqual(summary.fileTypeRows.map(\.label).sorted(), ["Markdown", "PDF"])
    }

    @MainActor
    private func syncAndAssertDetailLog(
        model: MainFileListModel,
        kind: MainExternalSyncEventKind,
        relativePath: String,
        fsEventID: Int64,
        expectedAction: String
    ) async throws {
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: kind,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))

        await model.syncExternalCreated(event)

        guard case let .synced(syncedEvent, fileID, _) = model.detailExternalCreateSyncState else {
            return XCTFail("expected synced state for \(kind.rawValue)")
        }
        XCTAssertEqual(syncedEvent, event)
        XCTAssertNotNil(fileID)
        try assertLoadedLog(model.detailLogState, fileID: XCTUnwrap(fileID), expectedAction: expectedAction)
        XCTAssertEqual(model.detailTabRequest, .automatic(.log))
        model.consumeDetailTabRequest(.automatic(.log))
        XCTAssertNil(model.detailTabRequest)
    }

    private func assertLoadedLog(
        _ state: MainDetailLogState,
        fileID: Int64,
        expectedAction: String
    ) {
        guard case let .loaded(loadedFileID, entries) = state else {
            return XCTFail("expected loaded change log")
        }

        XCTAssertEqual(loadedFileID, fileID)
        XCTAssertTrue(entries.contains { $0.action == expectedAction })
    }

    private func assertLoadedTags(
        _ state: DetailTagEditorState,
        fileID: Int64,
        expectedValues: [String]
    ) {
        guard case let .loaded(loadedFileID, tagSet) = state else {
            return XCTFail("expected loaded tag set")
        }

        XCTAssertEqual(loadedFileID, fileID)
        XCTAssertEqual(tagSet.fileID, fileID)
        XCTAssertEqual(tagSet.fileTags.map(\.value), expectedValues)
    }

    @MainActor
    private func makeDetailIntegrationModel(
        bridge: CoreBridge,
        repoURL: URL
    ) async throws -> MainFileListModel {
        let config = try await bridge.loadConfig(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        return MainFileListModel(
            opening: RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: []),
            fileLister: bridge,
            fileDetailer: bridge,
            tagStore: bridge,
            changeLogLister: bridge,
            externalChangesSyncer: bridge,
            errorMapper: bridge
        )
    }

    private func importDetailFixture(
        bridge: CoreBridge,
        repoURL: URL,
        sourceRootURL: URL,
        filename: String,
        content: String
    ) async throws -> FileEntrySnapshot {
        let sourceURL = sourceRootURL.appendingPathComponent(filename)
        try content.write(to: sourceURL, atomically: true, encoding: .utf8)
        return try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: filename,
            duplicateStrategy: .keepBoth
        )
    }
}

@MainActor
private func waitForDetailIntegrationNoteSave(_ model: DetailNoteModel) async {
    for _ in 0 ..< 200 {
        if model.state.saveStatus == .saved {
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func makeDetailIntegrationTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixDetailIntegration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension [DetailMetaMetadataRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

private extension RepositorySidebarRowSnapshot {
    static let s208IntegrationRoot = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
        slug: "__root__",
        displayName: "Repository",
        kind: "RepositoryRoot",
        relativePath: "",
        fileCount: 0,
        depth: 0,
        children: []
    ), depth: 0)
}

private extension RepositoryTreeNodeSnapshot {
    static let s208SidebarTagsTree = RepositoryTreeNodeSnapshot(
        slug: "__root__",
        displayName: "Repository",
        kind: "RepositoryRoot",
        relativePath: "",
        fileCount: 0,
        depth: 0,
        children: [
            RepositoryTreeNodeSnapshot(
                slug: "docs",
                displayName: "Documents",
                fileCount: 1,
                children: []
            )
        ]
    )
}

private extension SearchResultPageSnapshot {
    static func s208IntegrationSearchPage(_ filters: SearchFilterStateSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: "",
            totalCount: filters.tags.isEmpty ? 0 : 1,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

private extension SearchFacetsSnapshot {
    static func s208IntegrationFacets() -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: "",
            totalCount: 42,
            categories: [],
            fileKinds: [],
            tags: [
                SearchFacetCountSnapshot(
                    value: "finance",
                    label: "Finance",
                    count: 24,
                    selected: true,
                    disabled: false
                ),
                SearchFacetCountSnapshot(value: "tax", label: "Tax", count: 8, selected: true, disabled: false),
                SearchFacetCountSnapshot(value: "archive", label: "Archive", count: 0, selected: false, disabled: true)
            ],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: 1
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func s208FilterFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Could not load tags",
            severity: .medium,
            suggestedAction: "Retry tag filter loading.",
            recoverability: .retryable,
            rawContext: "S2-08 tags-filter"
        )
    }
}
