@testable import AreaMatrix
import XCTest

final class DetailMultiListFilesPageFeatureTests: XCTestCase {
    func testDetailMultiSelectBuildsMultiSelectionSummaryFromListFilesCoreAndGetFileDetailCoreDetails() {
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

    func testDetailMultiSelectKeepsPartialSummaryWhenGetFileDetailCoreMetadataIsUnavailable() {
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
    func testDetailMultiSelectMultiSelectionRefreshesEachSelectedFileThroughGetFileDetailCoreGetFile() async {
        let first = FileEntrySnapshot.detailMultiFixture(id: 33, currentName: "first.pdf", sizeBytes: 100)
        let second = FileEntrySnapshot.detailMultiFixture(id: 34, currentName: "second.pdf", sizeBytes: 100)
        let refreshedFirst = FileEntrySnapshot.detailMultiFixture(id: 33, currentName: "first.pdf", sizeBytes: 500)
        let refreshedSecond = FileEntrySnapshot.detailMultiFixture(id: 34, currentName: "second.pdf", sizeBytes: 700)
        let detailer = RecordingFileDetailer(results: [
            .success(refreshedFirst),
            .success(refreshedSecond)
        ])
        let model = MainFileListModel(
            opening: .detailMultiFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: detailer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([first.id, second.id])
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        await detailer.assertFileDetailRequests([
            FileDetailRequest(repoPath: "/tmp/repo", fileID: first.id),
            FileDetailRequest(repoPath: "/tmp/repo", fileID: second.id)
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
    func testDetailMultiSelectMapsGetFileDetailCoreFailureWhileKeepingAvailableMultiSelectionSummary() async {
        let first = FileEntrySnapshot.detailMultiFixture(id: 43, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMultiFixture(id: 44, currentName: "missing.pdf")
        let mapping = CoreErrorMappingSnapshot.detailMultiFileNotFound()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let detailer = RecordingFileDetailer(results: [
            .success(first),
            .failure(CoreError.FileNotFound(path: second.path))
        ])
        let model = MainFileListModel(
            opening: .detailMultiFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: detailer,
            errorMapper: mapper
        )

        await model.selectFiles([first.id, second.id])
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertEqual(model.detailErrorMapping, mapping)
        await mapper.assertMappedCoreErrors([CoreError.FileNotFound(path: second.path)])
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.paths, [first.path, second.path])
        XCTAssertFalse(model.isDetailLoading)
    }
}

private extension [MultiSelectionSummaryRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}
