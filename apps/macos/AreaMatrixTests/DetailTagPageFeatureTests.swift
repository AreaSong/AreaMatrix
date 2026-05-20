@testable import AreaMatrix
import XCTest

final class DetailTagPageFeatureTests: XCTestCase {
    @MainActor
    func testS207AddTagFailurePreservesPreviousStateAndDoesNotOfferUndo() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 207, currentName: "tag-fail.pdf")
        let initialTags = TagSetSnapshot.s207Fixture(fileID: detail.id, values: ["urgent"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            addResults: [.failure(CoreError.InvalidPath(reason: "tag contains illegal characters"))]
        )
        let mapping = CoreErrorMappingSnapshot.s207TagDb()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: mapper
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTags()
        await model.addSelectedFileTag("bad/tag")
        let addRequests = await tagStore.addRequests()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(addRequests, [DetailTagMutationRequest(repoPath: "/tmp/repo", fileID: detail.id, tag: "bad/tag")])
        XCTAssertEqual(model.detailTagEditorState, .failed(
            fileID: detail.id,
            operation: .add("bad/tag"),
            mapping,
            previous: initialTags
        ))
        XCTAssertEqual(model.detailTagEditorState.tagSet, initialTags)
        XCTAssertNil(model.detailTagUndoToast)
        XCTAssertEqual(mappedErrors, [CoreError.InvalidPath(reason: "tag contains illegal characters")])
        XCTAssertFalse(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: "bad/tag",
            state: model.detailTagEditorState
        ))
    }

    @MainActor
    func testS207RemoveTagFailureKeepsChipAndDoesNotOfferUndo() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 208, currentName: "remove-fail.pdf")
        let initialTags = TagSetSnapshot.s207Fixture(fileID: detail.id, values: ["clienta"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            removeResults: [.failure(CoreError.Db(message: "tag relation locked"))]
        )
        let mapping = CoreErrorMappingSnapshot.s207TagDb()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: mapping)
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTags()
        await model.removeSelectedFileTag("clienta")
        let removeRequests = await tagStore.removeRequests()

        XCTAssertEqual(removeRequests, [
            DetailTagMutationRequest(repoPath: "/tmp/repo", fileID: detail.id, tag: "clienta")
        ])
        XCTAssertEqual(model.detailTagEditorState, .failed(
            fileID: detail.id,
            operation: .remove("clienta"),
            mapping,
            previous: initialTags
        ))
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["clienta"])
        XCTAssertNil(model.detailTagUndoToast)
    }

    @MainActor
    func testS207SwitchingFilesClearsUndoToastAndBlocksStaleUndo() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 210, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 211, currentName: "second.pdf")
        let initialTags = TagSetSnapshot.s207Fixture(fileID: first.id, values: [])
        let addedTags = TagSetSnapshot.s207Fixture(fileID: first.id, values: ["clienta"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            addResults: [.success(addedTags)]
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: [first, second]),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([first.id])
        await model.loadSelectedFileTags()
        await model.addSelectedFileTag("clienta")
        XCTAssertEqual(model.detailTagUndoToast?.fileID, first.id)

        await model.selectFiles([second.id])
        XCTAssertNil(model.detailTagUndoToast)

        await model.undoLastDetailTagChange()
        let removeRequests = await tagStore.removeRequests()
        XCTAssertEqual(removeRequests, [])
    }

    @MainActor
    func testS207InputCommitPolicyClearsOnlyAfterSuccessfulAdd() {
        let fileID: Int64 = 209
        let failedState = DetailTagEditorState.failed(
            fileID: fileID,
            operation: .add("ClientA"),
            .s207TagDb(),
            previous: TagSetSnapshot.s207Fixture(fileID: fileID, values: [])
        )
        let loadedState = DetailTagEditorState.loaded(
            fileID: fileID,
            TagSetSnapshot.s207Fixture(fileID: fileID, values: ["clienta"])
        )

        XCTAssertFalse(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: " ClientA ",
            state: failedState
        ))
        XCTAssertTrue(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: " ClientA ",
            state: loadedState
        ))
    }
}

actor DetailTagFileDetailer: CoreFileDetailing {
    private let filesByID: [Int64: FileEntrySnapshot]

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }
}

struct DetailTagMutationRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var tag: String
}

actor DetailTagRecordingStore: CoreTagCRUD {
    enum Result {
        case success(TagSetSnapshot)
        case failure(Error)
    }

    private var listResults: [Result]
    private var addResults: [Result]
    private var removeResults: [Result]
    private var recordedAddRequests: [DetailTagMutationRequest] = []
    private var recordedRemoveRequests: [DetailTagMutationRequest] = []

    init(
        listResults: [Result] = [],
        addResults: [Result] = [],
        removeResults: [Result] = []
    ) {
        self.listResults = listResults
        self.addResults = addResults
        self.removeResults = removeResults
    }

    func listTags(repoPath _: String, fileID: Int64) async throws -> TagSetSnapshot {
        try consume(&listResults, fallbackFileID: fileID)
    }

    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        recordedAddRequests.append(DetailTagMutationRequest(repoPath: repoPath, fileID: fileID, tag: tag))
        return try consume(&addResults, fallbackFileID: fileID)
    }

    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        recordedRemoveRequests.append(DetailTagMutationRequest(repoPath: repoPath, fileID: fileID, tag: tag))
        return try consume(&removeResults, fallbackFileID: fileID)
    }

    func addRequests() -> [DetailTagMutationRequest] {
        recordedAddRequests
    }

    func removeRequests() -> [DetailTagMutationRequest] {
        recordedRemoveRequests
    }

    private func consume(_ results: inout [Result], fallbackFileID: Int64) throws -> TagSetSnapshot {
        guard !results.isEmpty else {
            return TagSetSnapshot.s207Fixture(fileID: fallbackFileID, values: [])
        }

        switch results.removeFirst() {
        case let .success(tagSet):
            return tagSet
        case let .failure(error):
            throw error
        }
    }
}

extension TagSetSnapshot {
    static func s207Fixture(fileID: Int64, values: [String]) -> TagSetSnapshot {
        let tags = values.map { value in
            TagRecordSnapshot(
                value: value,
                label: value,
                fileCount: 1,
                selected: true,
                disabled: false,
                updatedAt: 1_700_000_300
            )
        }
        return TagSetSnapshot(
            fileID: fileID,
            fileTags: tags,
            availableTags: tags,
            recentTags: tags,
            updatedAt: 1_700_000_300
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func s207TagDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法更新标签",
            severity: .medium,
            suggestedAction: "请保留输入并重试标签操作。",
            recoverability: .retryable,
            rawContext: "S2-07 C2-05 tag-crud"
        )
    }
}
