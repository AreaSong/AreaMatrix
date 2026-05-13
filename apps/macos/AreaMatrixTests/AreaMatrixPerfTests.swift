import AppKit
@testable import AreaMatrix
import CoreGraphics
import Darwin.Mach
import Foundation
import SwiftUI
import XCTest

final class AreaMatrixPerfTests: XCTestCase {
    @MainActor
    func testApplicationLaunchToFirstScreenBaselineUnderStage1Threshold() async throws {
        let repoURL = try makePerfTemporaryRepoURL("startup-empty")
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)

        if isDirectXCTestFallback {
            let elapsed = try await measureHostlessFirstScreenFallback(repoPath: repoURL.path)
            recordPerfMetric(
                name: "applicationLaunchToFirstScreen.hostlessFallback.emptyRepo",
                value: elapsed,
                threshold: Duration.milliseconds(1500)
            )
            XCTAssertLessThan(elapsed, Duration.milliseconds(1500))
            return
        }

        var measuredElapsed: Duration?
        var options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric()], options: options) {
            do {
                measuredElapsed = try measureApplicationLaunchToFirstScreen(repoPath: repoURL.path)
            } catch {
                XCTFail("AreaMatrix launch performance measurement failed: \(error)")
            }
        }

        let elapsed = try XCTUnwrap(measuredElapsed)
        recordPerfMetric(
            name: "applicationLaunchToFirstScreen.emptyRepo",
            value: elapsed,
            threshold: Duration.milliseconds(1500)
        )
        XCTAssertLessThan(elapsed, Duration.milliseconds(1500))
    }

    func testSingleFileImportBaselineUnderStage1Threshold() async throws {
        let repoURL = try makePerfTemporaryRepoURL("single-import-repo")
        let sourceRoot = try makePerfTemporaryRepoURL("single-import-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("invoice.pdf")
        try writePerfFile(sourceURL, sizeBytes: 1 * 1024 * 1024)
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)

        let elapsed = try await measureClock {
            _ = try await bridge.importCopiedFile(
                repoPath: repoURL.path,
                sourceURL: sourceURL,
                destination: .category("finance"),
                suggestedCategory: nil,
                overrideFilename: "invoice.pdf"
            )
        }

        recordPerfMetric(name: "importCopiedFile.1MiB", value: elapsed, threshold: Duration.milliseconds(200))
        XCTAssertLessThan(elapsed, Duration.milliseconds(200))
    }

    func testBatchImportAndListBaselineUnderStage1Threshold() async throws {
        let repoURL = try makePerfTemporaryRepoURL("batch-import-repo")
        let sourceRoot = try makePerfTemporaryRepoURL("batch-import-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURLs = try (0 ..< 100).map { index in
            let url = sourceRoot.appendingPathComponent(String(format: "batch-%03d.txt", index))
            try writePerfFile(url, sizeBytes: 4 * 1024, seed: index)
            return url
        }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)

        let elapsed = try await measureClock {
            for sourceURL in sourceURLs {
                _ = try await bridge.importCopiedFile(
                    repoPath: repoURL.path,
                    sourceURL: sourceURL,
                    destination: .category("docs"),
                    suggestedCategory: nil,
                    overrideFilename: sourceURL.lastPathComponent
                )
            }
            let filter = FileFilterSnapshot.perfCategory("docs", limit: 100)
            let listed = try await bridge.listFiles(repoPath: repoURL.path, filter: filter)
            XCTAssertEqual(listed.count, 100)
        }

        recordPerfMetric(
            name: "importCopiedFile.100x4KiB.plusList",
            value: elapsed,
            threshold: Duration.milliseconds(5000)
        )
        XCTAssertLessThan(elapsed, Duration.milliseconds(5000))
    }

    func testTreeAndListResponseBaselineUnderStage1Thresholds() async throws {
        let repoURL = try makePerfTemporaryRepoURL("tree-list")
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try writePerfRepositoryDataset(repoURL, count: 1000, sizeBytes: 128)
        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)

        let treeElapsed = try await measureClock {
            let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "en")
            XCTAssertEqual(tree.totalFileCount, 1000)
        }
        let listElapsed = try await measureClock {
            let filter = FileFilterSnapshot.perfCategory("docs", limit: 200)
            let listed = try await bridge.listFiles(repoPath: repoURL.path, filter: filter)
            XCTAssertEqual(listed.count, 200)
        }

        recordPerfMetric(name: "listTree.1kFiles", value: treeElapsed, threshold: Duration.milliseconds(30))
        let listFilesThreshold = isDirectXCTestFallback ? Duration.milliseconds(10) : Duration.milliseconds(5)
        recordPerfMetric(name: "listFiles.200Rows", value: listElapsed, threshold: listFilesThreshold)
        XCTAssertLessThan(treeElapsed, Duration.milliseconds(30))
        XCTAssertLessThan(listElapsed, listFilesThreshold)
    }

    func testMemoryBaselinesUnderStage1Thresholds() async throws {
        let bridge = CoreBridge()
        let idleRepo = try makePerfTemporaryRepoURL("memory-idle")
        let oneThousandRepo = try makePerfTemporaryRepoURL("memory-1k")
        let tenThousandRepo = try makePerfTemporaryRepoURL("memory-10k")
        defer {
            try? FileManager.default.removeItem(at: idleRepo)
            try? FileManager.default.removeItem(at: oneThousandRepo)
            try? FileManager.default.removeItem(at: tenThousandRepo)
        }

        try await bridge.initializeEmptyRepository(repoPath: idleRepo.path)
        _ = try await bridge.openConfiguredRepository(repoPath: idleRepo.path)
        try recordMemoryMetric(name: "memory.idle", thresholdMegabytes: 200)

        try writePerfRepositoryDataset(oneThousandRepo, count: 1000, sizeBytes: 128)
        try await bridge.adoptExistingRepository(repoPath: oneThousandRepo.path)
        _ = try await bridge.listFiles(repoPath: oneThousandRepo.path, filter: .perfCategory("docs", limit: 200))
        try recordMemoryMetric(name: "memory.1kFiles", thresholdMegabytes: 300)

        try writePerfRepositoryDataset(tenThousandRepo, count: 10000, sizeBytes: 128)
        try await bridge.adoptExistingRepository(repoPath: tenThousandRepo.path)
        _ = try await bridge.listTree(repoPath: tenThousandRepo.path, locale: "en")
        try recordMemoryMetric(name: "memory.10kFiles", thresholdMegabytes: 500)
    }

    private func measureClock(_ operation: () async throws -> Void) async rethrows -> Duration {
        let start = ContinuousClock.now
        try await operation()
        return start.duration(to: ContinuousClock.now)
    }
}

@MainActor
private func measureHostlessFirstScreenFallback(repoPath: String) async throws -> Duration {
    let start = ContinuousClock.now
    let model = OnboardingModel(
        settingsReader: PerfTestSettingsReader(repoPath: repoPath),
        helpOpener: PerfTestHelpOpener()
    )

    await model.bootstrapIfNeeded()
    try await waitForMainEmptyRoute(model)

    let hostingView = NSHostingView(rootView: MainWindow(model: model))
    hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
    hostingView.layoutSubtreeIfNeeded()
    hostingView.layoutSubtreeIfNeeded()

    return start.duration(to: ContinuousClock.now)
}

@MainActor
private func waitForMainEmptyRoute(
    _ model: OnboardingModel,
    timeout: TimeInterval = 1
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if case .mainEmpty = model.route { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw AreaMatrixPerfTestError.unexpectedFirstScreenRoute
}

private func measureApplicationLaunchToFirstScreen(repoPath: String) throws -> Duration {
    let start = ContinuousClock.now
    let application = try launchPerfApplication(repoPath: repoPath)
    let isReady = waitForFirstRepositoryWindow(processID: application.processIdentifier)
    let elapsed = start.duration(to: ContinuousClock.now)
    terminateLaunchedApplication(application)

    guard isReady else {
        throw AreaMatrixPerfTestError.firstScreenTimedOut
    }
    return elapsed
}

private func launchPerfApplication(repoPath: String) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["-AreaMatrix.repoPath", repoPath, "-ApplePersistenceIgnoreState", "YES"]
    configuration.environment = ProcessInfo.processInfo.environment.merging(
        ["AREAMATRIX_PERF_TEST": "1"]
    ) { _, new in new }

    let semaphore = DispatchSemaphore(value: 0)
    let applicationBox = ApplicationLaunchBox()
    try NSWorkspace.shared
        .openApplication(at: builtAreaMatrixAppURL(), configuration: configuration) { application, error in
            applicationBox.application = application
            applicationBox.error = error
            semaphore.signal()
        }
    guard semaphore.wait(timeout: .now() + 5) == .success else {
        throw AreaMatrixPerfTestError.appLaunchTimedOut
    }

    if let error = applicationBox.error { throw error }
    guard let application = applicationBox.application else {
        throw AreaMatrixPerfTestError.appLaunchReturnedNil
    }
    return application
}

private func builtAreaMatrixAppURL() throws -> URL {
    let productsURL = Bundle(for: AreaMatrixPerfTests.self).bundleURL.deletingLastPathComponent()
    let appURL = productsURL.appendingPathComponent("AreaMatrix.app", isDirectory: true)
    guard FileManager.default.fileExists(atPath: appURL.path) else {
        throw AreaMatrixPerfTestError.appBundleMissing(appURL.path)
    }
    return appURL
}

private func waitForFirstRepositoryWindow(processID: pid_t, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if hasVisibleWindow(forProcessID: processID) { return true }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return false
}

private func hasVisibleWindow(forProcessID processID: pid_t) -> Bool {
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return false
    }

    return windows.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID else {
            return false
        }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
            return true
        }
        let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
        let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
        return width > 0 && height > 0
    }
}

private func terminateLaunchedApplication(_ application: NSRunningApplication) {
    guard !application.isTerminated else { return }

    application.terminate()
    let deadline = Date().addingTimeInterval(1)
    while !application.isTerminated, Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    if !application.isTerminated {
        application.forceTerminate()
    }
}

private struct PerfTestSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

private struct PerfTestHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private extension FileFilterSnapshot {
    static func perfCategory(_ category: String, limit: Int64) -> FileFilterSnapshot {
        FileFilterSnapshot(
            category: category,
            includeDeleted: false,
            importedAfter: nil,
            importedBefore: nil,
            limit: limit,
            offset: 0
        )
    }
}

private func makePerfTemporaryRepoURL(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixPerfTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writePerfRepositoryDataset(_ repoURL: URL, count: Int, sizeBytes: Int) throws {
    for index in 0 ..< count {
        let parent = repoURL.appendingPathComponent("docs/bucket-\(index % 100)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let fileURL = parent.appendingPathComponent(String(format: "file-%05d.txt", index))
        try writePerfFile(fileURL, sizeBytes: sizeBytes, seed: index)
    }
}

private func writePerfFile(_ url: URL, sizeBytes: Int, seed: Int = 0) throws {
    guard sizeBytes > 0 else {
        try Data().write(to: url, options: .atomic)
        return
    }

    try Data((0 ..< sizeBytes).map { UInt8(($0 + seed) % 251) }).write(to: url, options: .atomic)
}

private func recordPerfMetric(name: String, value: Duration, threshold: Duration) {
    let milliseconds = Double(value.components.attoseconds) / 1_000_000_000_000_000
        + Double(value.components.seconds) * 1000
    let thresholdMilliseconds = Double(threshold.components.attoseconds) / 1_000_000_000_000_000
        + Double(threshold.components.seconds) * 1000
    let result = value < threshold ? "PASS" : "FAIL"
    print(String(
        format: "STAGE1_PERF name=\"%@\" value_ms=%.3f threshold_ms=%.3f result=%@",
        name,
        milliseconds,
        thresholdMilliseconds,
        result
    ))
}

private func recordMemoryMetric(name: String, thresholdMegabytes: Double) throws {
    let valueMegabytes = try ProcessMemoryGauge.residentMegabytes()
    let result = valueMegabytes < thresholdMegabytes ? "PASS" : "FAIL"
    print(String(
        format: "STAGE1_MEMORY name=\"%@\" value_mb=%.3f threshold_mb=%.3f result=%@",
        name,
        valueMegabytes,
        thresholdMegabytes,
        result
    ))
    XCTAssertLessThan(valueMegabytes, thresholdMegabytes)
}

private enum ProcessMemoryGauge {
    static func residentMegabytes() throws -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw ProcessMemoryGaugeError.taskInfoFailed(result)
        }
        return Double(info.resident_size) / 1_048_576
    }
}

private enum ProcessMemoryGaugeError: Error {
    case taskInfoFailed(kern_return_t)
}

private enum AreaMatrixPerfTestError: Error {
    case appBundleMissing(String), appLaunchTimedOut, appLaunchReturnedNil
    case firstScreenTimedOut, unexpectedFirstScreenRoute
}

private final class ApplicationLaunchBox: @unchecked Sendable {
    var application: NSRunningApplication?
    var error: Error?
}

private var isDirectXCTestFallback: Bool {
    ProcessInfo.processInfo.environment["AREAMATRIX_XCTEST_FALLBACK"] == "1"
}
