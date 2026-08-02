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
            L10n.string("GitHub")
        case .issue:
            L10n.string("Issue")
        case .discussions:
            L10n.string("Discussions")
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
    var message: LocalizedMessage
    var recovery: LocalizedMessage
    var copyableDetail: String
}

struct AboutSettingsVersionInfo: Equatable {
    private var appVersionValue: String?
    private var coreVersionValue: String?
    private var schemaVersionValue: String?

    var appVersion: String {
        get { appVersionValue ?? L10n.string("Unknown") }
        set { appVersionValue = newValue }
    }

    var coreVersion: String {
        get { coreVersionValue ?? L10n.string("Unknown") }
        set { coreVersionValue = newValue }
    }

    var schemaVersion: String {
        get { schemaVersionValue ?? L10n.string("Unknown") }
        set { schemaVersionValue = newValue }
    }

    init(appVersion: String?, coreVersion: String?, schemaVersion: String?) {
        appVersionValue = appVersion
        coreVersionValue = coreVersion
        schemaVersionValue = schemaVersion
    }

    static var unknown: AboutSettingsVersionInfo {
        AboutSettingsVersionInfo(
            appVersion: nil,
            coreVersion: nil,
            schemaVersion: nil
        )
    }
}

enum AboutSettingsActionFeedback: Equatable {
    case success(LocalizedMessage), failed(AboutSettingsError)
}

protocol AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String
}

protocol AboutStringCopying {
    @MainActor
    func copy(_ value: String) throws
}

@MainActor
final class AboutSettingsModel: ObservableObject {
    private static var coreErrorRecoveryAction: LocalizedMessage {
        L10n.message("Collect diagnostics...")
    }

    @Published private(set) var isLoadingVersionInfo = false
    @Published private(set) var versionInfo = AboutSettingsVersionInfo.unknown
    @Published private(set) var versionError: AboutSettingsError?
    @Published private(set) var actionFeedback: AboutSettingsActionFeedback?

    let repoPath: String
    private let appVersionReader: any AppVersionReading
    private let coreVersionReader: any CoreVersionReading
    private let metadataReader: any ExistingRepositoryMetadataReading
    private let externalLinkOpener: any AboutExternalLinkOpening
    private let stringCopier: any AboutStringCopying
    private let errorMapper: any CoreErrorMapping
    private let accessibilityAnnouncer: any AccessibilityAnnouncing

    init(
        repoPath: String,
        appVersionReader: any AppVersionReading = AboutSettingsPlatformServices.appVersionReader,
        coreVersionReader: any CoreVersionReading,
        metadataReader: any ExistingRepositoryMetadataReading = AboutSettingsPlatformServices.metadataReader,
        externalLinkOpener: any AboutExternalLinkOpening = AboutSettingsPlatformServices.externalLinkOpener,
        stringCopier: any AboutStringCopying = AboutSettingsPlatformServices.stringCopier,
        errorMapper: any CoreErrorMapping,
        accessibilityAnnouncer: any AccessibilityAnnouncing = AboutSettingsPlatformServices.accessibilityAnnouncer
    ) {
        self.repoPath = repoPath
        self.appVersionReader = appVersionReader
        self.coreVersionReader = coreVersionReader
        self.metadataReader = metadataReader
        self.externalLinkOpener = externalLinkOpener
        self.stringCopier = stringCopier
        self.errorMapper = errorMapper
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func load() async {
        isLoadingVersionInfo = true
        actionFeedback = nil
        versionError = nil

        var info = AboutSettingsVersionInfo(
            appVersion: appVersionReader.appVersion(),
            coreVersion: nil,
            schemaVersion: nil
        )
        var failures: [AboutSettingsError] = []

        do {
            info.coreVersion = try await coreVersionReader.coreVersion()
        } catch {
            await failures.append(mappedError(for: error, fallbackMessage: L10n.message("Core version unavailable")))
        }

        do {
            let metadata = try await metadataReader.metadata(repoPath: repoPath)
            info.schemaVersion = "v\(metadata.schemaVersion)"
        } catch {
            await failures.append(mappedError(for: error, fallbackMessage: L10n.message("Schema version unavailable")))
        }

        versionInfo = info
        versionError = Self.combinedVersionError(failures)
        isLoadingVersionInfo = false
    }

    func copyVersionSummary() {
        copyText(
            [
                L10n.format("App version: %@", versionInfo.appVersion),
                L10n.format("Core version: %@", versionInfo.coreVersion),
                L10n.format("Schema version: %@", versionInfo.schemaVersion)
            ].joined(separator: "\n")
        )
    }

    func openExternalLink(_ link: AboutExternalLink) {
        do {
            let openedURL = try externalLinkOpener.open(link: link)
            actionFeedback = .success(L10n.message("settings.about.linkOpened", arguments: [.string(link.title)]))
            _ = openedURL
        } catch {
            setFailure(AboutSettingsError(
                message: L10n.message("settings.about.linkOpenFailed", arguments: [.string(link.title)]),
                recovery: L10n.message("Copy the URL and open it in your browser."),
                copyableDetail: link.urlString
            ))
        }
    }

    func copyExternalLink(_ link: AboutExternalLink) {
        copyText(link.urlString)
    }

    func copyActionDetail(_ error: AboutSettingsError) {
        copyText(error.copyableDetail)
    }

    private func copyText(_ value: String) {
        do {
            try stringCopier.copy(value)
            actionFeedback = .success(L10n.message("Copied."))
        } catch {
            setFailure(AboutSettingsError(
                message: L10n.message("Copy failed"),
                recovery: L10n.message("Select the visible text and copy it manually."),
                copyableDetail: value
            ))
        }
    }

    private func setFailure(_ error: AboutSettingsError) {
        actionFeedback = .failed(error)
        accessibilityAnnouncer.announce(error.message)
    }

    private func mappedError(for error: Error, fallbackMessage: LocalizedMessage) async -> AboutSettingsError {
        if let display = await errorMapper.mapCoreErrorDisplayIfPresent(error) {
            return AboutSettingsError(
                message: fallbackMessage,
                recovery: Self.coreErrorRecoveryAction,
                copyableDetail: display.detail
            )
        }

        return AboutSettingsError(
            message: fallbackMessage,
            recovery: L10n.message(
                "Unexpected error. Retry or collect diagnostics.",
                technicalDetail: error.localizedDescription
            ),
            copyableDetail: error.localizedDescription
        )
    }

    private static func combinedVersionError(_ failures: [AboutSettingsError]) -> AboutSettingsError? {
        guard let first = failures.first else { return nil }
        guard failures.count > 1 else { return first }

        return AboutSettingsError(
            message: L10n.message("Some version values are unavailable"),
            recovery: L10n.message("Collect diagnostics if this persists."),
            copyableDetail: failures.map {
                "\(L10n.resolve($0.message)): \($0.copyableDetail)"
            }.joined(separator: "\n")
        )
    }
}

enum AboutSettingsPlatformError: Error, Equatable, LocalizedError {
    case invalidURL(String), openRejected(String), missingPath(String), copyRejected

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            L10n.format("Invalid URL: %@", value)
        case let .openRejected(value):
            L10n.format("System rejected opening: %@", value)
        case let .missingPath(path):
            L10n.format("Path is missing: %@", path)
        case .copyRejected:
            L10n.string("Pasteboard rejected the text.")
        }
    }
}
