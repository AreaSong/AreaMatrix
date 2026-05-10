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
