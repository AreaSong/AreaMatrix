@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import Foundation
import XCTest

final class RepositoryRemediationTests: XCTestCase {
    func testRepositoryWriteCoordinatorSerializesSameRepoAndRunsDifferentReposInParallel() async throws {
        let coordinator = RepositoryWriteCoordinator()
        let gate = RepositoryWriteOperationGate()
        let first = writeTask(coordinator: coordinator, gate: gate, repoPath: "/tmp/repo-a", id: "a1")
        await gate.waitForStartedCount(1)

        let second = writeTask(coordinator: coordinator, gate: gate, repoPath: "/tmp/repo-a/./", id: "a2")
        let parallel = writeTask(coordinator: coordinator, gate: gate, repoPath: "/tmp/repo-b", id: "b1")
        await gate.waitForStartedCount(2)
        let firstStartedIDs = await gate.startedIDs()
        XCTAssertEqual(Set(firstStartedIDs), ["a1", "b1"])

        await gate.release("a1")
        await gate.waitForStartedCount(3)
        let allStartedIDs = await gate.startedIDs()
        XCTAssertEqual(allStartedIDs, ["a1", "b1", "a2"])
        await gate.release("a2")
        await gate.release("b1")
        _ = try await (first.value, second.value, parallel.value)
    }

    func testRepositoryWriteCoordinatorCancelsWaiterWithoutInterruptingStartedOperation() async throws {
        let coordinator = RepositoryWriteCoordinator()
        let gate = RepositoryWriteOperationGate()
        let first = writeTask(coordinator: coordinator, gate: gate, repoPath: "/tmp/repo", id: "first")
        await gate.waitForStartedCount(1)
        let cancelled = writeTask(coordinator: coordinator, gate: gate, repoPath: "/tmp/repo", id: "cancelled")
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("A cancelled waiter must not start")
        } catch is CancellationError {}

        first.cancel()
        let next = writeTask(coordinator: coordinator, gate: gate, repoPath: "/tmp/repo", id: "next")
        await Task.yield()
        let startedBeforeRelease = await gate.startedIDs()
        XCTAssertEqual(startedBeforeRelease, ["first"])
        await gate.release("first")
        await gate.waitForStartedCount(2)
        let startedAfterRelease = await gate.startedIDs()
        XCTAssertEqual(startedAfterRelease, ["first", "next"])
        await gate.release("next")
        try await first.value
        try await next.value
    }

    func testICloudDownloaderWaitsForMaterializationAndTimesOut() async throws {
        let state = LockedICloudDownloadState(materializationResults: [false, false, true])
        let downloader = LocalICloudPlaceholderDownloader(
            startDownload: { state.start(url: $0) },
            isMaterialized: { state.isMaterialized(url: $0) },
            sleep: { await state.sleep(nanoseconds: $0) },
            pollIntervalNanoseconds: 1,
            maximumPollCount: 3
        )
        let sourceURL = URL(fileURLWithPath: "/tmp/cloud.pdf")

        try await downloader.downloadPlaceholder(at: sourceURL)
        XCTAssertEqual(state.startCount, 1)
        XCTAssertEqual(state.sleepCount, 1)

        let timeoutState = LockedICloudDownloadState(materializationResults: [false, false, false])
        let timeoutDownloader = LocalICloudPlaceholderDownloader(
            startDownload: { timeoutState.start(url: $0) },
            isMaterialized: { timeoutState.isMaterialized(url: $0) },
            sleep: { await timeoutState.sleep(nanoseconds: $0) },
            pollIntervalNanoseconds: 1,
            maximumPollCount: 2
        )
        do {
            try await timeoutDownloader.downloadPlaceholder(at: sourceURL)
            XCTFail("A placeholder that never materializes must time out")
        } catch let error as ICloudPlaceholderDownloadError {
            XCTAssertEqual(error, .timedOut(path: sourceURL.path))
        }
    }

    func testICloudDownloaderDoesNotStartMaterializedItemAndPropagatesCancellation() async throws {
        let materialized = LockedICloudDownloadState(materializationResults: [true])
        try await LocalICloudPlaceholderDownloader(
            startDownload: { materialized.start(url: $0) },
            isMaterialized: { materialized.isMaterialized(url: $0) },
            sleep: { await materialized.sleep(nanoseconds: $0) }
        ).downloadPlaceholder(at: URL(fileURLWithPath: "/tmp/local.pdf"))
        XCTAssertEqual(materialized.startCount, 0)

        let pending = LockedICloudDownloadState(materializationResults: [false, false])
        let downloader = LocalICloudPlaceholderDownloader(
            startDownload: { pending.start(url: $0) },
            isMaterialized: { pending.isMaterialized(url: $0) },
            sleep: { _ in throw CancellationError() },
            pollIntervalNanoseconds: 1,
            maximumPollCount: 2
        )
        do {
            try await downloader.downloadPlaceholder(at: URL(fileURLWithPath: "/tmp/cloud.pdf"))
            XCTFail("Cancellation must be propagated")
        } catch is CancellationError {}
    }

    func testModifiedAdvancesEventIDWithoutReplacingBusinessKind() throws {
        let created = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .created,
            relativePath: "docs/file.pdf",
            fsEventID: 10,
            cursorWatermark: 11
        ))
        let modified = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .modified,
            relativePath: created.relativePath,
            fsEventID: 11
        ))
        let window = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: "/tmp/repo",
            events: [created, modified],
            cursorWatermark: 11
        ))

        XCTAssertEqual(window.events.map(\.kind), [.created])
        XCTAssertEqual(window.events.map(\.fsEventID), [11])
    }

    @MainActor
    func testCancelledMainListDiagnosticsIgnoresLateResult() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(snapshotPath: "/tmp/diagnostics.zip")
        let collector = RemediationSuspendedDiagnosticsCollector(snapshot: snapshot)
        let model = remediationModel(diagnosticsCollector: collector)

        model.requestCurrentListDiagnostics()
        let collection = Task { await model.collectCurrentListDiagnostics() }
        await collector.waitForRequest()
        model.cancelCurrentListDiagnostics()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.diagnosticsState, .idle)
    }

    @MainActor
    func testExternalReloadDoesNotOverwriteNewSearchResults() async throws {
        let staleFile = FileEntrySnapshot.detailMetaFixture(id: 81, currentName: "stale.pdf")
        let searchFile = FileEntrySnapshot.detailMetaFixture(id: 82, currentName: "search.pdf")
        let lister = SuspendedRemediationFileLister(files: [staleFile])
        let model = remediationModel(fileLister: lister)
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: staleFile.path,
            fsEventID: 20
        ))

        let sync = Task { await model.syncExternalChanges([event]) }
        await lister.waitForRequest()
        model.searchState = .loaded(
            request: .testFixture(query: "current"),
            page: .testFixture(query: "current")
        )
        model.files = [searchFile]
        await lister.finish()
        let didSync = await sync.value
        XCTAssertTrue(didSync)
        XCTAssertEqual(model.files, [searchFile])
    }

    @MainActor
    func testLateExternalRemovalDoesNotTakeSelectionFromNewFile() async throws {
        let removed = FileEntrySnapshot.detailMetaFixture(id: 83, currentName: "removed.pdf")
        let selected = FileEntrySnapshot.detailMetaFixture(id: 84, currentName: "selected.pdf")
        let lister = SuspendedRemediationFileLister(files: [selected])
        let model = remediationModel(
            files: [removed, selected],
            fileLister: lister,
            fileDetailer: RemediationFileDetailer(files: [removed, selected]),
            syncResult: .testFixture(detectedDeletes: 1)
        )
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: removed.path,
            fsEventID: 21
        ))

        await model.selectFiles([removed.id])
        let sync = Task { await model.syncExternalChanges([event]) }
        await lister.waitForRequest()
        await model.selectFiles([selected.id])
        await lister.finish()
        let didSync = await sync.value
        XCTAssertTrue(didSync)
        XCTAssertEqual(model.selection, .single(selected.id))
        XCTAssertEqual(model.selectedFileDetail, selected)
    }

    @MainActor
    func testRepairCancelReturnsToOriginalMainListAndPreservesCurrentMapping() {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let mapping = CoreErrorMappingSnapshot.testFixture(kind: .db, userMessage: "List failed")
        let model = makeShellOnboardingModel()
        model.route = .mainList(opening)

        model.openMainRepositoryRepair(repoPath: opening.config.repoPath, mapping: mapping)
        guard case let .dbRepairConfirm(repairRoute) = model.route else {
            return XCTFail("Expected repair route")
        }
        XCTAssertEqual(repairRoute.mapping, mapping)
        XCTAssertEqual(repairRoute.returnRoute, .mainList(opening))

        model.returnFromDatabaseRepair(repairRoute)
        XCTAssertEqual(model.route, .mainList(opening))

        model.route = .mainEmpty(opening)
        model.openMainRepositoryRepair(repoPath: opening.config.repoPath)
        guard case let .dbRepairConfirm(emptyRepairRoute) = model.route else {
            return XCTFail("Expected repair route from empty repository")
        }
        XCTAssertEqual(emptyRepairRoute.returnRoute, .mainEmpty(opening))
        model.returnFromDatabaseRepair(emptyRepairRoute)
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }
}

@MainActor
private func remediationModel(
    files: [FileEntrySnapshot] = [],
    fileLister: any CoreFileListing = RecordingFileLister(files: []),
    fileDetailer: any CoreFileDetailing = RecordingFileDetailer(results: []),
    diagnosticsCollector: any CoreDiagnosticsCollecting = ImmediateDiagnosticsCollector(),
    syncResult: SyncResultSnapshot = .createdFixture()
) -> MainFileListModel {
    MainFileListModel(
        opening: .detailMetaFixture(repoPath: "/tmp/repo", files: files),
        fileLister: fileLister,
        fileDetailer: fileDetailer,
        externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(syncResult)),
        errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound()),
        diagnosticsCollector: diagnosticsCollector
    )
}

private func writeTask(
    coordinator: RepositoryWriteCoordinator,
    gate: RepositoryWriteOperationGate,
    repoPath: String,
    id: String
) -> Task<Void, Error> {
    Task {
        try await coordinator.withWriteAccess(repoPath: repoPath) {
            await gate.run(id)
        }
    }
}

private actor RepositoryWriteOperationGate {
    private var started: [String] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    func run(_ id: String) async {
        started.append(id)
        resumeStartWaiters()
        await withCheckedContinuation { releaseWaiters[id] = $0 }
    }

    func waitForStartedCount(_ count: Int) async {
        guard started.count < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func startedIDs() -> [String] {
        started
    }

    func release(_ id: String) {
        releaseWaiters.removeValue(forKey: id)?.resume()
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { started.count >= $0.0 }
        startWaiters.removeAll { started.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private actor RemediationSuspendedDiagnosticsCollector: CoreDiagnosticsCollecting {
    private let snapshot: DiagnosticsSnapshotSnapshot
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?
    private var didRequest = false

    init(snapshot: DiagnosticsSnapshotSnapshot) {
        self.snapshot = snapshot
    }

    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        didRequest = true
        requestWaiter?.resume()
        requestWaiter = nil
        await withCheckedContinuation { finishWaiter = $0 }
        return snapshot
    }

    func waitForRequest() async {
        guard !didRequest else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func finish() {
        finishWaiter?.resume()
        finishWaiter = nil
    }
}

private struct ImmediateDiagnosticsCollector: CoreDiagnosticsCollecting {
    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        .testFixture()
    }
}

private actor SuspendedRemediationFileLister: CoreFileListing {
    private let files: [FileEntrySnapshot]
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?
    private var didRequest = false

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        didRequest = true
        requestWaiter?.resume()
        requestWaiter = nil
        await withCheckedContinuation { finishWaiter = $0 }
        return files
    }

    func waitForRequest() async {
        guard !didRequest else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func finish() {
        finishWaiter?.resume()
        finishWaiter = nil
    }
}

private actor RemediationFileDetailer: CoreFileDetailing {
    private let filesByID: [Int64: FileEntrySnapshot]

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else { throw CoreError.FileNotFound(path: "\(fileID)") }
        return file
    }
}

private final class LockedICloudDownloadState: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool]
    private(set) var startCount = 0
    private(set) var sleepCount = 0

    init(materializationResults: [Bool]) {
        results = materializationResults
    }

    func start(url _: URL) {
        lock.withLock { startCount += 1 }
    }

    func isMaterialized(url _: URL) -> Bool {
        lock.withLock {
            guard !results.isEmpty else { return false }
            return results.removeFirst()
        }
    }

    func sleep(nanoseconds _: UInt64) async {
        lock.withLock { sleepCount += 1 }
    }
}
