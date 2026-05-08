import AppKit
import Combine
import Foundation

enum AboutExternalLink: String, CaseIterable, Equatable, Identifiable, Sendable {
    case github
    case issue
    case discussions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .github:
            return "GitHub"
        case .issue:
            return "Issue"
        case .discussions:
            return "Discussions"
        }
    }

    var systemImage: String {
        switch self {
        case .github:
            return "chevron.left.forwardslash.chevron.right"
        case .issue:
            return "exclamationmark.bubble"
        case .discussions:
            return "bubble.left.and.bubble.right"
        }
    }

    var urlString: String {
        switch self {
        case .github:
            return "https://github.com/AreaSong/AreaMatrix"
        case .issue:
            return "https://github.com/AreaSong/AreaMatrix/issues"
        case .discussions:
            return "https://github.com/AreaSong/AreaMatrix/discussions"
        }
    }
}

struct AboutSettingsError: Equatable, Sendable {
    var message: String
    var recovery: String
    var copyableDetail: String
}

struct AboutSettingsVersionInfo: Equatable, Sendable {
    var appVersion: String
    var coreVersion: String
    var schemaVersion: String

    static let unknown = AboutSettingsVersionInfo(
        appVersion: "Unknown", coreVersion: "Unknown", schemaVersion: "Unknown"
    )
}

struct AboutDiagnosticsExportContext: Equatable, Sendable {
    var versionInfo: AboutSettingsVersionInfo
    var versionIssue: String?
}

struct AboutDiagnosticsExportSnapshot: Equatable, Sendable {
    var exportPath: String
    var createdAt: Int64
    var warnings: [String]
}

enum AboutSettingsDiagnosticsState: Equatable, Sendable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(AboutDiagnosticsExportSnapshot)
    case failed(AboutSettingsError)

    var isConfirmingPrivacy: Bool {
        if case .confirmingPrivacy = self { return true }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}

enum AboutSettingsActionFeedback: Equatable, Sendable {
    case success(String), failed(AboutSettingsError)
}
protocol AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String
}

protocol AboutLogsOpening {
    @MainActor
    func logsPath(repoPath: String) -> String
    @MainActor
    func openLogs(repoPath: String) throws -> String
}

protocol AboutStringCopying {
    @MainActor
    func copy(_ value: String) throws
}

protocol AboutDiagnosticsRevealing {
    @MainActor
    func revealDiagnostics(at path: String) throws
}

protocol AboutDiagnosticsExporting: Sendable {
    func exportDiagnostics(context: AboutDiagnosticsExportContext) async throws -> AboutDiagnosticsExportSnapshot
}
struct LocalAboutCoreErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: error.localizedDescription,
            severity: .medium,
            suggestedAction: "Collect diagnostics...",
            recoverability: .retryable,
            rawContext: error.localizedDescription
        )
    }
}

@MainActor
final class AboutSettingsModel: ObservableObject {
    @Published private(set) var isLoadingVersionInfo = false
    @Published private(set) var versionInfo = AboutSettingsVersionInfo.unknown
    @Published private(set) var versionError: AboutSettingsError?
    @Published private(set) var diagnosticsState: AboutSettingsDiagnosticsState = .idle
    @Published private(set) var actionFeedback: AboutSettingsActionFeedback?

    let repoPath: String
    private let appVersionReader: any AppVersionReading
    private let coreVersionReader: any CoreVersionReading
    private let metadataReader: any ExistingRepositoryMetadataReading
    private let diagnosticsExporter: any AboutDiagnosticsExporting
    private let externalLinkOpener: any AboutExternalLinkOpening
    private let logsOpener: any AboutLogsOpening
    private let stringCopier: any AboutStringCopying
    private let diagnosticsRevealer: any AboutDiagnosticsRevealing
    private let errorMapper: any CoreErrorMapping
    private let accessibilityAnnouncer: any AccessibilityAnnouncing

    init(
        repoPath: String,
        appVersionReader: any AppVersionReading = BundleAppVersionReader(),
        coreVersionReader: any CoreVersionReading = CoreBridge(),
        metadataReader: any ExistingRepositoryMetadataReading = SQLiteExistingRepositoryMetadataReader(),
        diagnosticsExporter: any AboutDiagnosticsExporting = LocalAboutDiagnosticsExporter(),
        externalLinkOpener: any AboutExternalLinkOpening = NSWorkspaceAboutExternalLinkOpener(),
        logsOpener: any AboutLogsOpening = NSWorkspaceAboutLogsOpener(),
        stringCopier: any AboutStringCopying = NSPasteboardAboutStringCopier(),
        diagnosticsRevealer: any AboutDiagnosticsRevealing = NSWorkspaceAboutDiagnosticsRevealer(),
        errorMapper: any CoreErrorMapping = LocalAboutCoreErrorMapper(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer()
    ) {
        self.repoPath = repoPath
        self.appVersionReader = appVersionReader
        self.coreVersionReader = coreVersionReader
        self.metadataReader = metadataReader
        self.diagnosticsExporter = diagnosticsExporter
        self.externalLinkOpener = externalLinkOpener
        self.logsOpener = logsOpener
        self.stringCopier = stringCopier
        self.diagnosticsRevealer = diagnosticsRevealer
        self.errorMapper = errorMapper
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    var logsPath: String {
        logsOpener.logsPath(repoPath: repoPath)
    }

    var diagnosticsButtonTitle: String {
        diagnosticsState.isCollecting ? "Collecting diagnostics..." : "Collect diagnostics..."
    }

    func load() async {
        isLoadingVersionInfo = true
        actionFeedback = nil
        diagnosticsState = .idle
        versionError = nil

        var info = AboutSettingsVersionInfo(
            appVersion: appVersionReader.appVersion(),
            coreVersion: "Unknown",
            schemaVersion: "Unknown"
        )
        var failures: [AboutSettingsError] = []

        do {
            info.coreVersion = try await coreVersionReader.coreVersion()
        } catch {
            failures.append(await mappedError(for: error, fallbackMessage: "Core version unavailable"))
        }

        do {
            let metadata = try await metadataReader.metadata(repoPath: repoPath)
            info.schemaVersion = "v\(metadata.schemaVersion)"
        } catch {
            failures.append(await mappedError(for: error, fallbackMessage: "Schema version unavailable"))
        }

        versionInfo = info
        versionError = Self.combinedVersionError(failures)
        isLoadingVersionInfo = false
    }

    func copyVersionSummary() {
        copyText(
            """
            App version: \(versionInfo.appVersion)
            Core version: \(versionInfo.coreVersion)
            Schema version: \(versionInfo.schemaVersion)
            """
        )
    }

    func openExternalLink(_ link: AboutExternalLink) {
        do {
            let openedURL = try externalLinkOpener.open(link: link)
            actionFeedback = .success("\(link.title) opened.")
            _ = openedURL
        } catch {
            setFailure(AboutSettingsError(
                message: "\(link.title) link could not be opened",
                recovery: "Copy the URL and open it in your browser.",
                copyableDetail: link.urlString
            ))
        }
    }

    func copyExternalLink(_ link: AboutExternalLink) {
        copyText(link.urlString)
    }

    func openLogs() {
        do {
            let openedPath = try logsOpener.openLogs(repoPath: repoPath)
            actionFeedback = .success("Logs opened: \(openedPath)")
        } catch {
            setFailure(AboutSettingsError(
                message: "Open logs failed",
                recovery: "Copy the logs path and open it from Finder or Console.",
                copyableDetail: logsPath
            ))
        }
    }

    func copyLogsPath() {
        copyText(logsPath)
    }

    func requestDiagnosticsExport() {
        actionFeedback = nil
        guard !diagnosticsState.isCollecting else { return }
        diagnosticsState = .confirmingPrivacy
    }

    func cancelDiagnosticsExport() {
        if diagnosticsState.isConfirmingPrivacy {
            diagnosticsState = .idle
        }
    }

    func collectDiagnostics() async {
        guard diagnosticsState.isConfirmingPrivacy else { return }

        diagnosticsState = .collecting
        actionFeedback = nil
        do {
            let context = AboutDiagnosticsExportContext(
                versionInfo: versionInfo,
                versionIssue: versionError?.message
            )
            let snapshot = try await diagnosticsExporter.exportDiagnostics(context: context)
            diagnosticsState = .collected(snapshot)
            actionFeedback = .success("Diagnostics collected.")
        } catch {
            let mapped = await mappedError(for: error, fallbackMessage: "Diagnostics could not be exported")
            diagnosticsState = .failed(mapped)
            accessibilityAnnouncer.announce(mapped.message)
        }
    }

    func revealDiagnostics(_ snapshot: AboutDiagnosticsExportSnapshot) {
        do {
            try diagnosticsRevealer.revealDiagnostics(at: snapshot.exportPath)
            actionFeedback = .success("Diagnostics revealed in Finder.")
        } catch {
            setFailure(AboutSettingsError(
                message: "Diagnostics could not be revealed",
                recovery: "Copy the diagnostics path and open it from Finder.",
                copyableDetail: snapshot.exportPath
            ))
        }
    }

    func copyDiagnosticsPath(_ snapshot: AboutDiagnosticsExportSnapshot) {
        copyText(snapshot.exportPath)
    }

    func copyActionDetail(_ error: AboutSettingsError) {
        copyText(error.copyableDetail)
    }

    private func copyText(_ value: String) {
        do {
            try stringCopier.copy(value)
            actionFeedback = .success("Copied.")
        } catch {
            setFailure(AboutSettingsError(
                message: "Copy failed",
                recovery: "Select the visible text and copy it manually.",
                copyableDetail: value
            ))
        }
    }

    private func setFailure(_ error: AboutSettingsError) {
        actionFeedback = .failed(error)
        accessibilityAnnouncer.announce(error.message)
    }

    private func mappedError(for error: Error, fallbackMessage: String) async -> AboutSettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            let recovery = mapping.suggestedAction.isEmpty ? mapping.userMessage : mapping.suggestedAction
            return AboutSettingsError(
                message: fallbackMessage,
                recovery: recovery,
                copyableDetail: mapping.rawContext.isEmpty ? coreError.localizedDescription : mapping.rawContext
            )
        }

        return AboutSettingsError(
            message: fallbackMessage,
            recovery: error.localizedDescription,
            copyableDetail: error.localizedDescription
        )
    }

    private static func combinedVersionError(_ failures: [AboutSettingsError]) -> AboutSettingsError? {
        guard let first = failures.first else { return nil }
        guard failures.count > 1 else { return first }

        return AboutSettingsError(
            message: "Some version values are unavailable",
            recovery: "Collect diagnostics if this persists.",
            copyableDetail: failures.map { "\($0.message): \($0.copyableDetail)" }.joined(separator: "\n")
        )
    }
}

struct NSWorkspaceAboutExternalLinkOpener: AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        guard let url = URL(string: link.urlString) else {
            throw AboutSettingsPlatformError.invalidURL(link.urlString)
        }
        guard NSWorkspace.shared.open(url) else {
            throw AboutSettingsPlatformError.openRejected(link.urlString)
        }
        return link.urlString
    }
}

struct NSWorkspaceAboutLogsOpener: AboutLogsOpening {
    @MainActor
    func logsPath(repoPath: String) -> String {
        Self.logsURL(repoPath: repoPath).path
    }

    @MainActor
    func openLogs(repoPath: String) throws -> String {
        let url = Self.logsURL(repoPath: repoPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AboutSettingsPlatformError.missingPath(url.path)
        }
        guard NSWorkspace.shared.open(url) else {
            throw AboutSettingsPlatformError.openRejected(url.path)
        }
        return url.path
    }

    static func logsURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }
}

struct NSPasteboardAboutStringCopier: AboutStringCopying {
    @MainActor
    func copy(_ value: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(value, forType: .string) else {
            throw AboutSettingsPlatformError.copyRejected
        }
    }
}

struct NSWorkspaceAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    @MainActor
    func revealDiagnostics(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AboutSettingsPlatformError.missingPath(path)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct LocalAboutDiagnosticsExporter: AboutDiagnosticsExporting {
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    func exportDiagnostics(context: AboutDiagnosticsExportContext) async throws -> AboutDiagnosticsExportSnapshot {
        let createdAt = Int64(Date().timeIntervalSince1970)
        let exportURL = try Self.makeExportURL(baseDirectory: baseDirectory, createdAt: createdAt)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
        let reportURL = exportURL.appendingPathComponent("about-diagnostics.txt", isDirectory: false)
        try Self.report(context: context, createdAt: createdAt).write(
            to: reportURL,
            atomically: true,
            encoding: .utf8
        )

        return AboutDiagnosticsExportSnapshot(
            exportPath: exportURL.path,
            createdAt: createdAt,
            warnings: []
        )
    }

    private static func makeExportURL(baseDirectory: URL?, createdAt: Int64) throws -> URL {
        let directory = baseDirectory ?? defaultDiagnosticsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(
            "about-diagnostics-\(createdAt)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static func defaultDiagnosticsDirectory() -> URL {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (supportURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("AreaMatrix", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static func report(context: AboutDiagnosticsExportContext, createdAt: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        let createdAtLabel = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
        return """
        AreaMatrix About diagnostics
        Created at: \(createdAtLabel)
        App version: \(context.versionInfo.appVersion)
        Core version: \(context.versionInfo.coreVersion)
        Schema version: \(context.versionInfo.schemaVersion)
        Version issue: \(context.versionIssue ?? "none")
        User file contents: excluded
        Original file paths: redacted
        Automatic upload: disabled
        """
    }
}

enum AboutSettingsPlatformError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL(String)
    case openRejected(String)
    case missingPath(String)
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .openRejected(let value):
            return "System rejected opening: \(value)"
        case .missingPath(let path):
            return "Path is missing: \(path)"
        case .copyRejected:
            return "Pasteboard rejected the text."
        }
    }
}
