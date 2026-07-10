@testable import AreaMatrix
import XCTest

final class DetailMetaPageFeatureTests: XCTestCase {
    @MainActor
    func testDetailViewShowsCachedMetadataImmediatelyBeforeGetFileDetailCoreRefreshCompletes() async {
        let cached = FileEntrySnapshot.detailMetaFixture(id: 12, currentName: "cached.pdf")
        let refreshed = FileEntrySnapshot.detailMetaFixture(id: 12, currentName: "refreshed.pdf")
        let detailer = DetailMetaSuspendedDetailer(result: .success(refreshed))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [cached]),
            fileLister: NoopFileLister(),
            fileDetailer: detailer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        let selectionTask = Task { await model.selectFiles([cached.id]) }
        await detailer.waitForRequest()

        XCTAssertEqual(model.selection, .single(cached.id))
        XCTAssertEqual(model.selectedFileDetail, cached)
        XCTAssertTrue(model.isDetailLoading)

        await detailer.finish()
        await selectionTask.value

        XCTAssertEqual(model.selectedFileDetail, refreshed)
        XCTAssertEqual(model.files, [refreshed])
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertNil(model.detailErrorMapping)
    }

    @MainActor
    func testDetailViewKeepsCachedSummaryWhenGetFileDetailCoreGetFileFails() async {
        let cached = FileEntrySnapshot.detailMetaFixture(id: 13, currentName: "missing.pdf")
        let mapping = CoreErrorMappingSnapshot.detailMetaFileNotFound()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [cached]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: cached.path))),
            errorMapper: mapper
        )

        await model.selectFiles([cached.id])

        var missingCached = cached
        missingCached.availability = .missing
        XCTAssertEqual(model.selectedFileDetail, missingCached)
        XCTAssertEqual(model.detailErrorMapping, mapping)
        await mapper.assertRecordedErrors([CoreError.FileNotFound(path: cached.path)])
        XCTAssertFalse(model.isDetailLoading)
    }

    func testDetailViewMetadataRowsIncludeGetFileDetailCoreSourceAndStatus() {
        let indexed = FileEntrySnapshot.detailMetaFixture(
            id: 14,
            currentName: "indexed.pdf",
            storageMode: "Indexed",
            sourcePath: "~/Downloads/indexed.pdf"
        )

        let rows = detailMetaMetadataRows(for: indexed)

        XCTAssertEqual(rows.value(for: "Source"), "~/Downloads/indexed.pdf")
        XCTAssertEqual(rows.value(for: "Status"), "Index-only")
    }

    func testDetailViewMetadataRowsUseFallbackForMissingGetFileDetailCoreSource() {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 15, currentName: "no-source.pdf", sourcePath: nil)

        XCTAssertEqual(detailMetaMetadataRows(for: detail).value(for: "Source"), "Not available")
    }
}

private actor DetailMetaSuspendedDetailer: CoreFileDetailing {
    private let result: Swift.Result<FileEntrySnapshot, Error>
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    init(result: Swift.Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func waitForRequest() async {
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for detail metadata request" },
            value: {
                didReceiveRequest ? true : nil
            }
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
