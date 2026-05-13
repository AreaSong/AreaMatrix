@testable import AreaMatrix
import XCTest

final class DetailMultiListFilesPageFeatureTests: XCTestCase {
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
}
