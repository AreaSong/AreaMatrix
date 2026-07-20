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
        await mapper.assertMappedCoreErrors([CoreError.FileNotFound(path: cached.path)])
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

extension DetailMetaPageFeatureTests {
    func testMissingFileLocatePolicyOnlyShowsForMissingFiles() {
        var missing = FileEntrySnapshot.detailMetaFixture(id: 16, currentName: "missing.pdf")
        missing.availability = .missing
        let available = FileEntrySnapshot.detailMetaFixture(id: 17, currentName: "available.pdf")

        XCTAssertTrue(MainRepositoryDetailFileActionPolicy.shouldShowLocate(for: missing))
        XCTAssertFalse(MainRepositoryDetailFileActionPolicy.shouldShowLocate(for: available))
    }

    @MainActor
    func testLocateMissingFileCancellationDoesNotCallRelink() async {
        let missing = missingDetailMetaFile(id: 18)
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .failure(DetailMetaMissingFileTestError.unexpectedRelink)
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: nil)
        let model = missingFileModel(file: missing, recoverer: recoverer, picker: picker)

        await model.locateMissingFile(fileID: missing.id)

        XCTAssertEqual(model.missingFileRelinkState, .idle)
        await recoverer.assertRelinkRequests([])
        XCTAssertEqual(picker.lastKnownPaths, ["/tmp/repo/docs/contracts/missing.pdf"])
    }

    @MainActor
    func testLocateMissingFileHashMismatchKeepsMissingSelection() async {
        let missing = missingDetailMetaFile(id: 19)
        let replacementURL = URL(fileURLWithPath: "/tmp/replacement.pdf")
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .success(.detailMetaHashMismatch(fileID: missing.id))
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: replacementURL)
        let model = missingFileModel(file: missing, recoverer: recoverer, picker: picker)

        await model.locateMissingFile(fileID: missing.id)

        XCTAssertEqual(
            model.missingFileRelinkState,
            .hashMismatch(fileID: missing.id, message: "Selected file does not match the missing record.")
        )
        XCTAssertEqual(model.selectedFileDetail, missing)
        await recoverer.assertRelinkRequests([
            .init(repoPath: "/tmp/repo", fileID: missing.id, newPath: replacementURL.path)
        ])
    }

    @MainActor
    func testLocateMissingFileRejectsUndownloadedICloudSelectionWithoutCoreCall() async {
        let missing = missingDetailMetaFile(id: 20)
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .failure(DetailMetaMissingFileTestError.unexpectedRelink)
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: URL(fileURLWithPath: "/tmp/file.pdf.icloud"))
        let model = missingFileModel(file: missing, recoverer: recoverer, picker: picker)

        await model.locateMissingFile(fileID: missing.id)

        XCTAssertEqual(
            model.missingFileRelinkState,
            .unavailable(fileID: missing.id, message: "Download the selected file in Finder, then choose Locate again.")
        )
        await recoverer.assertRelinkRequests([])
    }

    @MainActor
    func testLocateMissingFileSuccessRefreshesListDetailAndChangeLog() async {
        let missing = missingDetailMetaFile(id: 21)
        var recovered = missing
        recovered.path = "docs/contracts/recovered.pdf"
        recovered.currentName = "recovered.pdf"
        recovered.availability = .available
        let replacementURL = URL(fileURLWithPath: "/tmp/repo/docs/contracts/recovered.pdf")
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .success(.detailMetaRelinked(fileID: missing.id, currentPath: recovered.path))
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: replacementURL)
        let lister = MainListRecordingFileLister(files: [recovered])
        let model = missingFileModel(
            file: missing,
            recoverer: recoverer,
            picker: picker,
            fileLister: lister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(recovered))
        )

        await model.locateMissingFile(fileID: missing.id)

        XCTAssertEqual(model.missingFileRelinkState, .idle)
        XCTAssertEqual(model.files, [recovered])
        XCTAssertEqual(model.selectedFileDetail, recovered)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.statusBanner, .relinkedMissingFile(fileID: missing.id))
        guard case let .loaded(fileID, entries) = model.detailLogState else {
            return XCTFail("expected refreshed change log")
        }
        XCTAssertEqual(fileID, missing.id)
        XCTAssertEqual(entries, [])
        await lister.assertNoFileListRequests()
    }

    @MainActor
    func testLocateMissingFileSuccessRefreshesRowWithoutOverwritingNewSelection() async {
        let missing = missingDetailMetaFile(id: 22)
        var recovered = missing
        recovered.currentName = "recovered.pdf"
        recovered.availability = .available
        let other = FileEntrySnapshot.detailMetaFixture(id: 23, currentName: "other.pdf")
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .success(.detailMetaRelinked(fileID: missing.id, currentPath: recovered.path))
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: URL(fileURLWithPath: "/tmp/recovered.pdf"))
        let detailer = DetailMetaSuspendedDetailer(result: .success(recovered))
        let model = missingFileModel(file: missing, recoverer: recoverer, picker: picker, fileDetailer: detailer)
        model.files = [missing, other]

        let locateTask = Task { await model.locateMissingFile(fileID: missing.id) }
        await detailer.waitForRequest()
        model.clearDetail()
        model.selection = .single(other.id)
        model.selectedFileDetail = other
        model.detailErrorMapping = .detailMetaFileNotFound()
        await detailer.finish()
        await locateTask.value

        XCTAssertEqual(model.files, [recovered, other])
        XCTAssertEqual(model.selection, .single(other.id))
        XCTAssertEqual(model.selectedFileDetail, other)
        XCTAssertEqual(model.detailErrorMapping, .detailMetaFileNotFound())
        XCTAssertEqual(model.missingFileRelinkState, .idle)
        XCTAssertNil(model.statusBanner)
    }

    @MainActor
    func testLocateMissingFileRefreshFailureAfterSelectionChangeDoesNotLeaveBusyState() async {
        let missing = missingDetailMetaFile(id: 25)
        let other = FileEntrySnapshot.detailMetaFixture(id: 26, currentName: "other.pdf")
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .success(.detailMetaRelinked(fileID: missing.id, currentPath: missing.path))
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: URL(fileURLWithPath: "/tmp/recovered.pdf"))
        let detailer = DetailMetaSuspendedDetailer(
            result: .failure(CoreError.FileNotFound(path: missing.path))
        )
        let mapper = StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        let model = missingFileModel(
            file: missing,
            recoverer: recoverer,
            picker: picker,
            fileDetailer: detailer,
            errorMapper: mapper
        )

        let locateTask = Task { await model.locateMissingFile(fileID: missing.id) }
        await detailer.waitForRequest()
        model.selection = .single(other.id)
        model.selectedFileDetail = other
        await detailer.finish()
        await locateTask.value

        XCTAssertEqual(model.selection, .single(other.id))
        XCTAssertEqual(model.selectedFileDetail, other)
        XCTAssertEqual(model.missingFileRelinkState, .idle)
        await mapper.assertMappedCoreErrors([])
    }

    @MainActor
    func testLocateMissingFileOnLaterPagePreservesLoadedPagination() async {
        let firstPage = detailMetaPage(0 ..< 50)
        var secondPage = detailMetaPage(50 ..< 100)
        var missing = secondPage[10]
        missing.availability = .missing
        secondPage[10] = missing
        var recovered = missing
        recovered.currentName = "recovered-60.pdf"
        recovered.availability = .available
        let recoverer = DetailMetaMissingFileRecoverer(
            state: .success(.detailMetaFixture(file: missing)),
            report: .success(.detailMetaRelinked(fileID: missing.id, currentPath: recovered.path))
        )
        let picker = DetailMetaMissingFilePicker(selectedURL: URL(fileURLWithPath: "/tmp/recovered-60.pdf"))
        let lister = MainListRecordingFileLister(results: [.success(firstPage), .success(secondPage)])
        let model = missingFileModel(
            file: missing,
            recoverer: recoverer,
            picker: picker,
            fileLister: lister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(recovered))
        )

        await model.loadCurrentCategory("docs")
        await model.loadMoreCurrentCategory()
        model.selection = .single(missing.id)
        model.selectedFileDetail = missing
        await model.locateMissingFile(fileID: missing.id)

        XCTAssertEqual(model.files.count, 100)
        XCTAssertEqual(model.files[60], recovered)
        XCTAssertEqual(model.nextFilePageOffset, 100)
        XCTAssertTrue(model.hasMore)
        await lister.assertFileListFilters([detailMetaPageFilter(offset: 0), detailMetaPageFilter(offset: 50)])
    }

    @MainActor
    func testLocateMissingFileDoesNotStartForReadOnlyOrWriteLockedFile() async {
        let missing = missingDetailMetaFile(id: 24)
        let scenarios: [(isReadOnly: Bool, writeLockedFileIDs: Set<Int64>)] = [
            (true, []),
            (false, [missing.id])
        ]

        for scenario in scenarios {
            let recoverer = DetailMetaMissingFileRecoverer(
                state: .failure(DetailMetaMissingFileTestError.unexpectedRelink),
                report: .failure(DetailMetaMissingFileTestError.unexpectedRelink)
            )
            let picker = DetailMetaMissingFilePicker(selectedURL: URL(fileURLWithPath: "/tmp/recovered.pdf"))
            let model = missingFileModel(
                file: missing,
                recoverer: recoverer,
                picker: picker,
                isReadOnly: scenario.isReadOnly,
                writeLockedFileIDs: scenario.writeLockedFileIDs
            )

            await model.locateMissingFile(fileID: missing.id)

            XCTAssertEqual(model.missingFileRelinkState, .idle)
            await recoverer.assertStateRequestCount(0)
            await recoverer.assertRelinkRequests([])
            XCTAssertEqual(picker.lastKnownPaths, [])
        }
    }

    @MainActor
    private func missingFileModel(
        file: FileEntrySnapshot,
        recoverer: DetailMetaMissingFileRecoverer,
        picker: DetailMetaMissingFilePicker,
        fileLister: any CoreFileListing = NoopFileLister(),
        fileDetailer: (any CoreFileDetailing)? = nil,
        errorMapper: any CoreErrorMapping = StaticCoreErrorMapper(mapping: .detailMetaFileNotFound()),
        isReadOnly: Bool = false,
        writeLockedFileIDs: Set<Int64> = []
    ) -> MainFileListModel {
        var opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [file])
        opening.isReadOnly = isReadOnly
        opening.writeLockedFileIDs = writeLockedFileIDs
        let model = MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: fileDetailer ?? DetailMetaImmediateDetailer(result: .success(file)),
            missingFileRecoverer: recoverer,
            missingFilePicker: picker,
            changeLogLister: RecordingChangeLogLister(entries: []),
            errorMapper: errorMapper
        )
        model.selection = .single(file.id)
        model.selectedFileDetail = file
        model.detailErrorMapping = .detailMetaFileNotFound()
        return model
    }

    private func missingDetailMetaFile(id: Int64) -> FileEntrySnapshot {
        var file = FileEntrySnapshot.detailMetaFixture(id: id, currentName: "missing.pdf")
        file.availability = .missing
        return file
    }
}

private enum DetailMetaMissingFileTestError: Error {
    case unexpectedRelink
}

private actor DetailMetaMissingFileRecoverer: CoreMissingFileRecovering {
    struct RelinkRequest: Equatable {
        var repoPath: String
        var fileID: Int64
        var newPath: String
    }

    private let state: Result<MissingFileStateSnapshot, Error>
    private let report: Result<MissingFileRecoveryReportSnapshot, Error>
    private var stateRequestCount = 0
    private var relinkRequests: [RelinkRequest] = []

    init(
        state: Result<MissingFileStateSnapshot, Error>,
        report: Result<MissingFileRecoveryReportSnapshot, Error>
    ) {
        self.state = state
        self.report = report
    }

    func missingFileState(repoPath _: String, fileID _: Int64) async throws -> MissingFileStateSnapshot {
        stateRequestCount += 1
        return try state.get()
    }

    func relinkMissingFile(
        repoPath: String,
        fileID: Int64,
        newPath: String
    ) async throws -> MissingFileRecoveryReportSnapshot {
        relinkRequests.append(.init(repoPath: repoPath, fileID: fileID, newPath: newPath))
        return try report.get()
    }

    func assertStateRequestCount(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(stateRequestCount, expected, file: file, line: line)
    }

    func assertRelinkRequests(
        _ expected: [RelinkRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(relinkRequests, expected, file: file, line: line)
    }
}

@MainActor
private final class DetailMetaMissingFilePicker: RepositoryMissingFilePicking {
    private let selectedURL: URL?
    private(set) var lastKnownPaths: [String?] = []

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func chooseReplacementFile(lastKnownPath: String?) -> URL? {
        lastKnownPaths.append(lastKnownPath)
        return selectedURL
    }
}

private extension MissingFileStateSnapshot {
    static func detailMetaFixture(file: FileEntrySnapshot) -> Self {
        Self(
            fileID: file.id,
            relativePath: file.path,
            lastKnownPath: "/tmp/repo/\(file.path)",
            expectedHashSha256: file.hashSha256,
            reason: .pathMissing,
            canLocate: true
        )
    }
}

private extension MissingFileRecoveryReportSnapshot {
    static func detailMetaHashMismatch(fileID: Int64) -> Self {
        Self(
            fileID: fileID,
            status: .hashMismatch,
            previousPath: "docs/contracts/missing.pdf",
            currentPath: nil,
            hashMatched: false,
            fileDeleted: false,
            message: "Selected file does not match the missing record."
        )
    }

    static func detailMetaRelinked(fileID: Int64, currentPath: String) -> Self {
        Self(
            fileID: fileID,
            status: .relinked,
            previousPath: "docs/contracts/missing.pdf",
            currentPath: currentPath,
            hashMatched: true,
            fileDeleted: false,
            message: "Missing file relinked."
        )
    }
}

private func detailMetaPage(_ range: Range<Int64>) -> [FileEntrySnapshot] {
    range.map { FileEntrySnapshot.detailMetaFixture(id: $0, currentName: "\($0).pdf") }
}

private func detailMetaPageFilter(offset: Int64) -> FileFilterSnapshot {
    var filter = FileFilterSnapshot.currentCategory("docs")
    filter.offset = offset
    return filter
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
