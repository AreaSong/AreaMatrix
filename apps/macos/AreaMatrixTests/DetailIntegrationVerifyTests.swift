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

final class DetailIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testDetailViewToDetailMultiSelectDetailLoopUsesRealCoreBridgeWithoutFinalMock() async throws {
        let context = try await makeDetailIntegrationContext()
        defer {
            removeTestTemporaryItems(context.repoURL, context.sourceRootURL)
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
        let noteModel = makeDetailNoteTestModel(
            repoPath: repoURL.path,
            noteStore: bridge,
            errorMapper: bridge
        )
        await noteModel.load(file: file, writeBlock: nil)
        noteModel.createNote()
        noteModel.updateDraft("# Detail note")
        await waitForDetailNoteSaved(noteModel)

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

        await context.model.detailTagModel.loadSelectedFileTags()
        assertLoadedTags(context.model.detailTagModel.editorState, fileID: file.id, expectedValues: [])

        await context.model.detailTagModel.addSelectedFileTag(" ClientA ")
        assertLoadedTags(context.model.detailTagModel.editorState, fileID: file.id, expectedValues: ["clienta"])
        XCTAssertEqual(context.model.detailTagModel.undoToast?.message, #"Added tag "clienta"."#)

        let addedTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(addedTags.fileTags.map(\.value), ["clienta"])

        await context.model.detailTagModel.undoLastDetailTagChange()
        assertLoadedTags(context.model.detailTagModel.editorState, fileID: file.id, expectedValues: [])
        XCTAssertNil(context.model.detailTagModel.undoToast)
        let undoneAddedTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(undoneAddedTags.fileTags, [])

        await context.model.detailTagModel.addSelectedFileTag("clienta")
        assertLoadedTags(context.model.detailTagModel.editorState, fileID: file.id, expectedValues: ["clienta"])

        await context.model.detailTagModel.removeSelectedFileTag("clienta")
        assertLoadedTags(context.model.detailTagModel.editorState, fileID: file.id, expectedValues: [])
        XCTAssertEqual(context.model.detailTagModel.undoToast?.message, #"Removed tag "clienta"."#)

        let removedTags = try await context.bridge.listTags(repoPath: context.repoURL.path, fileID: file.id)
        XCTAssertEqual(removedTags.fileTags, [])

        await context.model.detailTagModel.undoLastDetailTagChange()
        assertLoadedTags(context.model.detailTagModel.editorState, fileID: file.id, expectedValues: ["clienta"])
        XCTAssertNil(context.model.detailTagModel.undoToast)
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
            fsEventID: 23001
        )

        try FileManager.default.moveItem(at: externalURL, to: renamedURL)
        try await syncAndAssertDetailLog(
            model: context.model,
            kind: .renamed,
            relativePath: "docs/external-renamed.txt",
            fsEventID: 23002
        )

        try removeTestTemporaryItem(renamedURL)
        try await syncAndAssertDetailLog(
            model: context.model,
            kind: .removed,
            relativePath: "docs/external-renamed.txt",
            fsEventID: 23003
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
        fsEventID: Int64
    ) async throws {
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: kind,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        let detailLogStateBeforeSync = model.detailLogState
        let detailTabRequestBeforeSync = model.detailTabRequest

        await model.syncExternalCreated(event)

        XCTAssertEqual(model.detailExternalCreateSyncState, .idle)
        XCTAssertEqual(model.detailLogState, detailLogStateBeforeSync)
        XCTAssertEqual(model.detailTabRequest, detailTabRequestBeforeSync)
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

extension DetailIntegrationVerifyTests {
    @MainActor
    func testMissingFileLocateRelinksRealCoreMetadataWithoutMutatingReplacementFile() async throws {
        let repoURL = try makeDetailIntegrationTemporaryRepositoryURL()
        let sourceRootURL = try makeDetailIntegrationTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL, sourceRootURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await importDetailFixture(
            bridge: bridge,
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            filename: "missing.txt",
            content: "matching content"
        )
        let originalURL = repoURL.appendingPathComponent(imported.path)
        try removeTestTemporaryItem(originalURL)
        let replacementURL = repoURL.appendingPathComponent("docs/recovered.txt")
        try "matching content".write(to: replacementURL, atomically: true, encoding: .utf8)
        let model = try await makeMissingFileIntegrationModel(
            bridge: bridge,
            repoURL: repoURL,
            picker: DetailIntegrationMissingFilePicker(selectedURL: replacementURL)
        )

        await model.loadCurrentCategory("docs")
        await model.selectFiles([imported.id])
        await model.locateMissingFile(fileID: imported.id)

        let refreshed = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)
        XCTAssertEqual(refreshed.path, "docs/recovered.txt")
        XCTAssertEqual(refreshed.availability, .available)
        XCTAssertEqual(model.selectedFileDetail, refreshed)
        XCTAssertEqual(model.statusBanner, .relinkedMissingFile(fileID: imported.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertEqual(try String(contentsOf: replacementURL, encoding: .utf8), "matching content")
        guard case let .loaded(fileID, entries) = model.detailLogState else {
            return XCTFail("expected relink change log")
        }
        XCTAssertEqual(fileID, imported.id)
        XCTAssertTrue(entries.contains { $0.detailJSON.contains("missing_file_relinked") })
    }

    @MainActor
    func testMissingFileLocateHashMismatchKeepsRealCoreMetadataAndUserFilesUnchanged() async throws {
        let repoURL = try makeDetailIntegrationTemporaryRepositoryURL()
        let sourceRootURL = try makeDetailIntegrationTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL, sourceRootURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await importDetailFixture(
            bridge: bridge,
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            filename: "missing.txt",
            content: "original content"
        )
        let originalURL = repoURL.appendingPathComponent(imported.path)
        try removeTestTemporaryItem(originalURL)
        let replacementURL = repoURL.appendingPathComponent("docs/not-the-same.txt")
        try "different content".write(to: replacementURL, atomically: true, encoding: .utf8)
        let model = try await makeMissingFileIntegrationModel(
            bridge: bridge,
            repoURL: repoURL,
            picker: DetailIntegrationMissingFilePicker(selectedURL: replacementURL)
        )

        await model.loadCurrentCategory("docs")
        await model.selectFiles([imported.id])
        await model.locateMissingFile(fileID: imported.id)

        guard case .hashMismatch = model.missingFileRelinkState else {
            return XCTFail("expected hash mismatch state")
        }
        let retained = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)
        XCTAssertEqual(retained.path, imported.path)
        XCTAssertEqual(retained.availability, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertEqual(try String(contentsOf: replacementURL, encoding: .utf8), "different content")
        let entries = try await bridge.listChanges(
            repoPath: repoURL.path,
            filter: .detailLog(fileID: imported.id)
        )
        XCTAssertFalse(entries.contains { $0.detailJSON.contains("missing_file_relinked") })
    }

    @MainActor
    private func makeMissingFileIntegrationModel(
        bridge: CoreBridge,
        repoURL: URL,
        picker: DetailIntegrationMissingFilePicker
    ) async throws -> MainFileListModel {
        let config = try await bridge.loadConfig(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        return MainFileListModel(
            opening: RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: []),
            fileLister: bridge,
            fileDetailer: bridge,
            missingFileRecoverer: bridge,
            missingFilePicker: picker,
            changeLogLister: bridge,
            errorMapper: bridge
        )
    }
}

@MainActor
private final class DetailIntegrationMissingFilePicker: RepositoryMissingFilePicking {
    private let selectedURL: URL?

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func chooseReplacementFile(lastKnownPath _: String?) -> URL? {
        selectedURL
    }
}

private func makeDetailIntegrationTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixDetailIntegration")
}
