@testable import AreaMatrix
import XCTest

final class DetailMultiListFilesPageFeatureTests: XCTestCase {
    func testS209BatchAddTagsValidationNormalizesAndBlocksInvalidPendingTags() {
        let first = BatchTagValidation.pendingStateAfterAdding(
            input: " ClientA ",
            pendingTags: [],
            catalog: .s209TagCatalogFixture(fileID: 31),
            disabledReason: nil
        )
        let catalog = TagSetSnapshot.s209TagCatalogFixture(fileID: 31)
        let duplicate = BatchTagValidation.pendingStateAfterAdding(
            input: "clienta",
            pendingTags: first.pendingTags,
            catalog: catalog,
            disabledReason: nil
        )
        let invalid = BatchTagValidation.pendingStateAfterAdding(
            input: "bad/tag",
            pendingTags: first.pendingTags,
            catalog: catalog,
            disabledReason: nil
        )
        let blocked = BatchTagValidation.pendingStateAfterAdding(
            input: "blocked",
            pendingTags: [],
            catalog: catalog,
            disabledReason: nil
        )
        let reserved = BatchTagValidation.pendingStateAfterAdding(
            input: ".areamatrix",
            pendingTags: [],
            catalog: catalog,
            disabledReason: nil
        )

        XCTAssertEqual(first, BatchTagPendingState(input: "", pendingTags: ["clienta"], fieldError: nil))
        XCTAssertEqual(duplicate.fieldError, "Tag already selected.")
        XCTAssertEqual(invalid.fieldError, "Tag name is invalid.")
        XCTAssertEqual(blocked.fieldError, "Tag store is read-only.")
        XCTAssertEqual(reserved.fieldError, "Tag name is invalid.")
        XCTAssertFalse(BatchTagValidation.canApply(
            isApplying: false, disabledReason: nil, input: " unsaved ", pendingTags: first.pendingTags,
            fieldError: nil, selectedCount: 2
        ))
        XCTAssertFalse(BatchTagValidation.canApply(
            isApplying: false, disabledReason: nil, input: "", pendingTags: ["clienta", "ClientA"],
            fieldError: nil, selectedCount: 2
        ))
        XCTAssertEqual(BatchTagValidation.normalizedTagsForApply(["bad/tag"]), .failure("Tag name is invalid."))
    }

    @MainActor
    func testS209BatchAddTagsLoadsCandidatesAndAppliesThroughC206CoreTagCRUD() async {
        let store = S209RecordingBatchTagStore(results: [
            .tagSet(.success(.s209TagCatalogFixture(fileID: 31))),
            .success(.s209Fixture())
        ])
        let catalog = await BatchTagCatalogAction.load(
            repoPath: "/tmp/repo",
            fileIDs: [31, 32],
            tagStore: store,
            errorMapper: DetailMetaErrorMapper(mapping: .s209TagDb())
        )
        let candidates = BatchTagValidation.visibleCandidates(
            input: "",
            catalog: catalog.tagSet,
            pendingTags: ["urgent"]
        )
        let result = await BatchAddTagsAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [32, 31],
            tags: ["urgent", "clienta"],
            tagStore: store,
            errorMapper: DetailMetaErrorMapper(mapping: .s209TagDb())
        )
        let requests = await store.batchRequests()
        let listRequests = await store.listRequests()

        XCTAssertEqual(listRequests, ["31"])
        XCTAssertEqual(candidates.map(\.value), ["urgent", "clienta"])
        XCTAssertTrue(candidates.first { $0.value == "urgent" }?.selected == true)
        XCTAssertEqual(requests, ["/tmp/repo|32,31|urgent,clienta"])
        XCTAssertEqual(result.report?.addedCount, 3)
        XCTAssertEqual(result.report?.skippedCount, 1)
        XCTAssertEqual(result.report?.undoToken, "undo-c2-06")
        XCTAssertNil(result.failure)
        guard let report = result.report else {
            return XCTFail("Expected C2-06 batch_add_tags report")
        }
        let presentation = BatchMutationReportPresentation(report: report)
        XCTAssertEqual(presentation.addedSummaryText, "Added to 2 files (3 tag relations)")
        XCTAssertEqual(presentation.skippedSummaryText, "1 file already had these tags")
        XCTAssertEqual(presentation.failedSummaryText, "0 failed")
    }

    func testS209BatchAddTagsValidationBlocksReadOnlyAndDuplicatePendingTags() {
        let readOnly = BatchTagValidation.pendingStateAfterAdding(
            input: "urgent",
            pendingTags: [],
            catalog: .s209TagCatalogFixture(fileID: 31),
            disabledReason: MainFileWriteActionDisabledReason.repoReadOnly.rawValue
        )
        let chips = BatchTagValidation.pendingChips(
            pendingTags: ["urgent", "urgent"],
            disabledReason: nil
        )

        XCTAssertEqual(readOnly.fieldError, "Tag store is read-only.")
        XCTAssertEqual(chips.map(\.status), [.ready, .alreadySelected])
        XCTAssertFalse(BatchTagValidation.canApply(
            isApplying: false, disabledReason: MainFileWriteActionDisabledReason.repoReadOnly.rawValue,
            input: "", pendingTags: ["urgent"], fieldError: nil, selectedCount: 2
        ))
        let duplicateApply = BatchTagValidation.normalizedTagsForApply(["urgent", "urgent"])
        XCTAssertEqual(duplicateApply, .failure("Tag already selected."))
    }

    @MainActor
    func testS209BatchAddTagsMapsC206FailureWithoutMockingSuccess() async {
        let mapping = CoreErrorMappingSnapshot.s209TagDb()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let store = S209RecordingBatchTagStore(results: [
            .failure(CoreError.Db(message: "tag metadata locked"))
        ])
        let result = await BatchAddTagsAction.apply(
            repoPath: "/tmp/repo",
            fileIDs: [31, 32],
            tags: ["urgent"],
            tagStore: store,
            errorMapper: mapper
        )
        let requests = await store.batchRequests()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(requests, ["/tmp/repo|31,32|urgent"])
        XCTAssertNil(result.report)
        XCTAssertEqual(result.failure, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "tag metadata locked")])
    }

    func testS115BuildsMultiSelectionSummaryFromC111AndC112Details() {
        let pdf = FileEntrySnapshot.detailMultiFixture(
            id: 31,
            currentName: "contract.pdf",
            sizeBytes: 200,
            storageMode: "Copied",
            importedAt: 1_700_000_000
        )
        let indexed = FileEntrySnapshot.detailMultiFixture(
            id: 32,
            currentName: "notes.md",
            sizeBytes: 100,
            storageMode: "Indexed",
            importedAt: 1_700_086_400
        )

        let summary = MultiSelectionDetailSummary(
            selection: .multiple([pdf.id, indexed.id]),
            files: [indexed, pdf]
        )

        XCTAssertEqual(summary.title, "2 个文件已选中")
        XCTAssertEqual(summary.subtitle, "docs 中的 2 个项目")
        XCTAssertEqual(summary.paths, [pdf.path, indexed.path])
        XCTAssertEqual(
            summary.statisticRows.value(for: "Total size"),
            ByteCountFormatter.string(fromByteCount: 300, countStyle: .file)
        )
        XCTAssertEqual(summary.statisticRows.value(for: "Categories"), "docs")
        XCTAssertEqual(summary.statisticRows.value(for: "Storage modes"), "Copied, Indexed")
        XCTAssertEqual(summary.fileTypeRows, [
            MultiSelectionSummaryRow(label: "Markdown", value: "1"),
            MultiSelectionSummaryRow(label: "PDF", value: "1")
        ])
        XCTAssertEqual(summary.warningMessages, ["某些条目的来源路径可能在资料库外"])
    }

    func testS115KeepsPartialSummaryWhenC112MetadataIsUnavailable() {
        let available = FileEntrySnapshot.detailMultiFixture(
            id: 41,
            currentName: "available.pdf",
            availability: .available
        )
        let missing = FileEntrySnapshot.detailMultiFixture(
            id: 42,
            currentName: "missing.pdf",
            availability: .missing
        )

        let summary = MultiSelectionDetailSummary(
            selection: .multiple([available.id, missing.id, 99]),
            files: [available, missing],
            isUpdating: true
        )

        XCTAssertTrue(summary.isUpdating)
        XCTAssertEqual(summary.selectedCount, 3)
        XCTAssertEqual(summary.unresolvedMetadataCount, 1)
        XCTAssertEqual(summary.warningMessages, [
            "部分选中项无法读取元数据",
            "选中的文件中有 1 个缺失条目"
        ])
    }

    @MainActor
    func testS115MultiSelectionRefreshesEachSelectedFileThroughC112GetFile() async {
        let first = FileEntrySnapshot.detailMultiFixture(id: 33, currentName: "first.pdf", sizeBytes: 100)
        let second = FileEntrySnapshot.detailMultiFixture(id: 34, currentName: "second.pdf", sizeBytes: 100)
        let refreshedFirst = FileEntrySnapshot.detailMultiFixture(id: 33, currentName: "first.pdf", sizeBytes: 500)
        let refreshedSecond = FileEntrySnapshot.detailMultiFixture(id: 34, currentName: "second.pdf", sizeBytes: 700)
        let detailer = DetailMultiRecordingDetailer(results: [
            .success(refreshedFirst),
            .success(refreshedSecond)
        ])
        let model = MainFileListModel(
            opening: .detailMultiFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: detailer,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([first.id, second.id])
        let requests = await detailer.recordedRequests()
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        XCTAssertEqual(requests, [
            DetailMultiFileDetailRequest(repoPath: "/tmp/repo", fileID: first.id),
            DetailMultiFileDetailRequest(repoPath: "/tmp/repo", fileID: second.id)
        ])
        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertEqual(summary.statisticRows.value(for: "Total size"), ByteCountFormatter.string(
            fromByteCount: refreshedFirst.sizeBytes + refreshedSecond.sizeBytes,
            countStyle: .file
        ))
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertNil(model.detailErrorMapping)
    }

    @MainActor
    func testS115MapsC112FailureWhileKeepingAvailableMultiSelectionSummary() async {
        let first = FileEntrySnapshot.detailMultiFixture(id: 43, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMultiFixture(id: 44, currentName: "missing.pdf")
        let mapping = CoreErrorMappingSnapshot.detailMultiFileNotFound()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let detailer = DetailMultiRecordingDetailer(results: [
            .success(first),
            .failure(CoreError.FileNotFound(path: second.path))
        ])
        let model = MainFileListModel(
            opening: .detailMultiFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: detailer,
            errorMapper: mapper
        )

        await model.selectFiles([first.id, second.id])
        let mappedErrors = await mapper.recordedErrors()
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.FileNotFound(path: second.path)])
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.paths, [first.path, second.path])
        XCTAssertFalse(model.isDetailLoading)
    }
}

private struct DetailMultiFileDetailRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

private actor S209RecordingBatchTagStore: CoreTagCRUD {
    enum Result {
        case tagSet(Swift.Result<TagSetSnapshot, Error>)
        case success(BatchMutationReportSnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedBatchRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot {
        recordedListRequests.append("\(fileID)")
        guard !results.isEmpty else {
            throw CoreError.Db(message: "missing list_tags result")
        }

        guard case let .tagSet(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "expected list_tags result before batch_add_tags")
        }
        return try result.get()
    }

    func addTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        throw CoreError.Internal(message: "S2-09 C2-06 must use batch_add_tags")
    }

    func removeTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        throw CoreError.Internal(message: "S2-09 C2-06 must not remove tags")
    }

    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot {
        let ids = fileIDs.map(String.init).joined(separator: ",")
        recordedBatchRequests.append("\(repoPath)|\(ids)|\(tags.joined(separator: ","))")
        guard !results.isEmpty else {
            throw CoreError.Db(message: "missing batch_add_tags result")
        }

        switch results.removeFirst() {
        case .tagSet:
            throw CoreError.Internal(message: "expected batch_add_tags result after list_tags")
        case let .success(report):
            return report
        case let .failure(error):
            throw error
        }
    }

    func batchRequests() -> [String] {
        recordedBatchRequests
    }

    func listRequests() -> [String] {
        recordedListRequests
    }
}

private actor DetailMultiRecordingDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [DetailMultiFileDetailRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(DetailMultiFileDetailRequest(repoPath: repoPath, fileID: fileID))
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case let .success(file):
            return file
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [DetailMultiFileDetailRequest] {
        requests
    }
}

private extension RepositoryOpeningResult {
    static func detailMultiFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
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
                fileCount: Int64(files.count),
                children: []
            ),
            currentCategoryFiles: files
        )
    }
}

private extension FileEntrySnapshot {
    static func detailMultiFixture(
        id: Int64,
        currentName: String,
        sizeBytes: Int64 = 256,
        storageMode: String = "Copied",
        importedAt: Int64 = 1_700_000_000,
        availability: FileAvailabilitySnapshot = .available
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: sizeBytes,
            hashSha256: "detail-multi-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: importedAt,
            updatedAt: importedAt,
            availability: availability
        )
    }
}

private extension [MultiSelectionSummaryRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailMultiFileNotFound() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "部分选中项无法读取元数据",
            severity: .medium,
            suggestedAction: "刷新当前选择，确认文件是否仍在资料库中。",
            recoverability: .refreshRequired,
            rawContext: "S1-15 C1-12 get_file"
        )
    }

    static func s209TagDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法批量添加标签",
            severity: .medium,
            suggestedAction: "请保留待添加标签并重试。",
            recoverability: .retryable,
            rawContext: "S2-09 C2-06 batch_add_tags"
        )
    }

}

extension TagSetSnapshot {
    static func s209TagCatalogFixture(fileID: Int64) -> TagSetSnapshot {
        let urgent = TagRecordSnapshot.s209Tag(value: "urgent", fileCount: 3)
        let client = TagRecordSnapshot.s209Tag(value: "clienta", fileCount: 1)
        return TagSetSnapshot(
            fileID: fileID,
            fileTags: [],
            availableTags: [urgent, client, .s209Tag(value: "blocked", fileCount: 0, disabled: true)],
            recentTags: [urgent, client],
            updatedAt: 1_700_000_000
        )
    }
}

private extension TagRecordSnapshot {
    static func s209Tag(value: String, fileCount: Int64, disabled: Bool = false) -> TagRecordSnapshot {
        TagRecordSnapshot(
            value: value,
            label: value,
            fileCount: fileCount,
            selected: false,
            disabled: disabled,
            updatedAt: 1_700_000_000
        )
    }
}

private extension BatchMutationReportSnapshot {
    static func s209Fixture() -> BatchMutationReportSnapshot {
        BatchMutationReportSnapshot(
            requestedFileCount: 2,
            requestedTagCount: 2,
            addedCount: 3,
            skippedCount: 1,
            failedCount: 0,
            itemResults: [
                BatchMutationItemResultSnapshot(fileID: 31, tag: "urgent", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 31, tag: "clienta", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 32, tag: "urgent", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 32, tag: "clienta", status: .alreadyHadTag, error: nil)
            ],
            undoToken: "undo-c2-06"
        )
    }
}
