import AppKit
import CoreGraphics
import Foundation

private struct ProbeOptions {
    let appPath: String
    let thresholdMilliseconds: Double
    let timeoutSeconds: TimeInterval
    let metricName: String
    let launchMode: LaunchMode
}

private enum LaunchMode: String {
    case workspace
    case executable
}

private enum ProbeError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case appBundleMissing(String)
    case launchTimedOut
    case firstScreenTimedOut
    case launchFailed(String, domain: String?, code: Int?)
    case processLaunchFailed(String)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .unknownArgument(let argument):
            return "unknown argument \(argument)"
        case .appBundleMissing(let path):
            return "app bundle not found at \(path)"
        case .launchTimedOut:
            return "application launch callback timed out"
        case .firstScreenTimedOut:
            return "first visible window did not appear before timeout"
        case .launchFailed(let message, let domain, let code):
            let domainText = domain.map { " domain=\($0)" } ?? ""
            let codeText = code.map { " code=\($0)" } ?? ""
            return "application launch failed: \(message)\(domainText)\(codeText)"
        case .processLaunchFailed(let message):
            return "application executable launch failed: \(message)"
        }
    }
}

private func parseOptions() throws -> ProbeOptions {
    var appPath: String?
    var thresholdMilliseconds = 1_500.0
    var timeoutSeconds: TimeInterval = 5
    var metricName = "applicationLaunchToFirstScreen.welcomeRoute"
    var launchMode = LaunchMode.workspace
    var index = 1

    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        switch argument {
        case "--app":
            appPath = try requiredValue(after: argument, at: &index)
        case "--threshold-ms":
            thresholdMilliseconds = Double(try requiredValue(after: argument, at: &index)) ?? thresholdMilliseconds
        case "--timeout-seconds":
            timeoutSeconds = Double(try requiredValue(after: argument, at: &index)) ?? timeoutSeconds
        case "--metric-name":
            metricName = try requiredValue(after: argument, at: &index)
        case "--launch-mode":
            let rawValue = try requiredValue(after: argument, at: &index)
            guard let parsed = LaunchMode(rawValue: rawValue) else {
                throw ProbeError.unknownArgument(rawValue)
            }
            launchMode = parsed
        default:
            throw ProbeError.unknownArgument(argument)
        }
        index += 1
    }

    guard let appPath else { throw ProbeError.missingValue("--app") }
    return ProbeOptions(
        appPath: appPath,
        thresholdMilliseconds: thresholdMilliseconds,
        timeoutSeconds: timeoutSeconds,
        metricName: metricName,
        launchMode: launchMode
    )
}

private func requiredValue(after flag: String, at index: inout Int) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < CommandLine.arguments.count else {
        throw ProbeError.missingValue(flag)
    }
    index = valueIndex
    return CommandLine.arguments[valueIndex]
}

private func runProbe(_ options: ProbeOptions) throws {
    let appURL = URL(fileURLWithPath: options.appPath, isDirectory: true)
    guard FileManager.default.fileExists(atPath: appURL.path) else {
        throw ProbeError.appBundleMissing(appURL.path)
    }

    let start = DispatchTime.now()
    let launched = try launchApplication(appURL: appURL, mode: options.launchMode)
    let isReady = waitForFirstWindow(processID: launched.processIdentifier, timeout: options.timeoutSeconds)
    let elapsedMilliseconds = elapsedMilliseconds(since: start)
    launched.terminate()

    guard isReady else { throw ProbeError.firstScreenTimedOut }
    let result = elapsedMilliseconds < options.thresholdMilliseconds ? "PASS" : "FAIL"
    print(String(
        format: "STAGE1_PERF name=\"%@\" value_ms=%.3f threshold_ms=%.3f result=%@",
        options.metricName,
        elapsedMilliseconds,
        options.thresholdMilliseconds,
        result
    ))

    if result != "PASS" {
        exit(1)
    }
}

private func launchApplication(appURL: URL, mode: LaunchMode) throws -> LaunchedApplication {
    switch mode {
    case .workspace:
        return try launchWorkspaceApplication(appURL: appURL)
    case .executable:
        return try launchExecutableApplication(appURL: appURL)
    }
}

private func launchWorkspaceApplication(appURL: URL) throws -> LaunchedApplication {
    let executableURL = appURL.appendingPathComponent("Contents/MacOS/AreaMatrix")
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
        throw ProbeError.appBundleMissing(executableURL.path)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    configuration.arguments = ["-ApplePersistenceIgnoreState", "YES"]
    configuration.environment = ProcessInfo.processInfo.environment.merging(
        ["AREAMATRIX_PERF_TEST": "1"]
    ) { _, new in new }

    let semaphore = DispatchSemaphore(value: 0)
    let box = ApplicationLaunchBox()
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, error in
        box.application = application
        box.error = error
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 5) == .success else {
        throw ProbeError.launchTimedOut
    }
    if let error = box.error {
        let nsError = error as NSError
        throw ProbeError.launchFailed(nsError.localizedDescription, domain: nsError.domain, code: nsError.code)
    }
    guard let application = box.application else {
        throw ProbeError.launchFailed("NSWorkspace returned no running application", domain: nil, code: nil)
    }
    return RunningWorkspaceApplication(application: application)
}

private func launchExecutableApplication(appURL: URL) throws -> LaunchedApplication {
    let executableURL = appURL.appendingPathComponent("Contents/MacOS/AreaMatrix")
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
        throw ProbeError.appBundleMissing(executableURL.path)
    }

    let process = Process()
    process.executableURL = executableURL
    process.currentDirectoryURL = executableURL.deletingLastPathComponent()
    process.arguments = ["-ApplePersistenceIgnoreState", "YES"]
    process.environment = ProcessInfo.processInfo.environment.merging(
        ["AREAMATRIX_PERF_TEST": "1"]
    ) { _, new in new }

    do {
        try process.run()
    } catch {
        throw ProbeError.processLaunchFailed(error.localizedDescription)
    }
    NSRunningApplication(processIdentifier: process.processIdentifier)?
        .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    return RunningProcessApplication(process: process)
}

private func waitForFirstWindow(processID: pid_t, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if hasVisibleWindow(processID: processID) {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return false
}

private func hasVisibleWindow(processID: pid_t) -> Bool {
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

private protocol LaunchedApplication {
    var processIdentifier: pid_t { get }
    func terminate()
}

private struct RunningWorkspaceApplication: LaunchedApplication {
    let application: NSRunningApplication

    var processIdentifier: pid_t { application.processIdentifier }

    func terminate() {
        guard !application.isTerminated else { return }

        application.terminate()
        let deadline = Date().addingTimeInterval(1)
        while !application.isTerminated && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !application.isTerminated {
            application.forceTerminate()
        }
    }
}

private struct RunningProcessApplication: LaunchedApplication {
    let process: Process

    var processIdentifier: pid_t { process.processIdentifier }

    func terminate() {
        guard process.isRunning else { return }

        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if process.isRunning {
            process.interrupt()
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private func elapsedMilliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

private final class ApplicationLaunchBox: @unchecked Sendable {
    var application: NSRunningApplication?
    var error: Error?
}

do {
    try runProbe(parseOptions())
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
