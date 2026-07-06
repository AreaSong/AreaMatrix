import Combine
import Foundation

enum AboutExternalLink: String, CaseIterable, Equatable, Identifiable {
    case github
    case issue
    case discussions

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .github:
            "GitHub"
        case .issue:
            "Issue"
        case .discussions:
            "Discussions"
        }
    }

    var systemImage: String {
        switch self {
        case .github:
            "chevron.left.forwardslash.chevron.right"
        case .issue:
            "exclamationmark.bubble"
        case .discussions:
            "bubble.left.and.bubble.right"
        }
    }

    var urlString: String {
        switch self {
        case .github:
            "https://github.com/AreaSong/AreaMatrix"
        case .issue:
            "https://github.com/AreaSong/AreaMatrix/issues"
        case .discussions:
            "https://github.com/AreaSong/AreaMatrix/discussions"
        }
    }
}

struct AboutSettingsError: Equatable {
    var message: String
    var recovery: String
    var copyableDetail: String
}

struct AboutSettingsVersionInfo: Equatable {
    var appVersion: String
    var coreVersion: String
    var schemaVersion: String

    static let unknown = AboutSettingsVersionInfo(
        appVersion: "Unknown", coreVersion: "Unknown", schemaVersion: "Unknown"
    )
}

struct AboutDiagnosticsExportContext: Equatable {
    var versionInfo: AboutSettingsVersionInfo
    var versionIssue: String?
}

struct AboutDiagnosticsExportSnapshot: Equatable {
    var exportPath: String
    var createdAt: Int64
    var warnings: [String]
}

enum AboutSettingsDiagnosticsState: Equatable {
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

enum AboutSettingsActionFeedback: Equatable {
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

@MainActor
final class AboutSettingsModel: ObservableObject {
    private static let coreErrorRecoveryAction = "Collect diagnostics..."

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
        appVersionReader: any AppVersionReading = AboutSettingsPlatformServices.appVersionReader,
        coreVersionReader: any CoreVersionReading = AppCoreServices.coreVersionReader,
        metadataReader: any ExistingRepositoryMetadataReading = AboutSettingsPlatformServices.metadataReader,
        diagnosticsExporter: any AboutDiagnosticsExporting = AboutSettingsPlatformServices.diagnosticsExporter,
        externalLinkOpener: any AboutExternalLinkOpening = AboutSettingsPlatformServices.externalLinkOpener,
        logsOpener: any AboutLogsOpening = AboutSettingsPlatformServices.logsOpener,
        stringCopier: any AboutStringCopying = AboutSettingsPlatformServices.stringCopier,
        diagnosticsRevealer: any AboutDiagnosticsRevealing = AboutSettingsPlatformServices.diagnosticsRevealer,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = AboutSettingsPlatformServices.accessibilityAnnouncer
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
            await failures.append(mappedError(for: error, fallbackMessage: "Core version unavailable"))
        }

        do {
            let metadata = try await metadataReader.metadata(repoPath: repoPath)
            info.schemaVersion = "v\(metadata.schemaVersion)"
        } catch {
            await failures.append(mappedError(for: error, fallbackMessage: "Schema version unavailable"))
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
        if let display = await errorMapper.mapCoreErrorDisplayIfPresent(error) {
            return AboutSettingsError(
                message: fallbackMessage,
                recovery: Self.coreErrorRecoveryAction,
                copyableDetail: display.detail
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

enum AboutSettingsPlatformError: Error, Equatable, LocalizedError {
    case invalidURL(String), openRejected(String), missingPath(String), copyRejected

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            "Invalid URL: \(value)"
        case let .openRejected(value):
            "System rejected opening: \(value)"
        case let .missingPath(path):
            "Path is missing: \(path)"
        case .copyRejected:
            "Pasteboard rejected the text."
        }
    }
}
