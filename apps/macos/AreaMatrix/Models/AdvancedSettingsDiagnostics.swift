import AppKit
import Combine
import Foundation

protocol CoreVersionReading: Sendable {
    func coreVersion() async throws -> String
}

protocol AppVersionReading: Sendable {
    func appVersion() -> String
}

protocol AdvancedSettingsLogFolderOpening {
    @MainActor
    func openLogsFolder(repoPath: String) throws -> String
}

protocol AdvancedSettingsDiagnosticSummaryCopying {
    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws
}

struct AdvancedSettingsVersionInfo: Equatable {
    var appVersion: String
    var coreVersion: String
    var repoSchemaVersion: Int64?

    static let unknown = AdvancedSettingsVersionInfo(
        appVersion: "Unknown",
        coreVersion: "Unknown",
        repoSchemaVersion: nil
    )

    var repoSchemaVersionLabel: String {
        repoSchemaVersion.map { "v\($0)" } ?? "Unknown"
    }
}

enum AdvancedSettingsDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(AdvancedSettingsError)

    var isConfirmingPrivacy: Bool {
        if case .confirmingPrivacy = self { return true }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}

enum AdvancedSettingsActionFeedback: Equatable {
    case success(String)
    case failed(AdvancedSettingsError)
}

struct AISettingsError: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

enum AISettingsActionFeedback: Equatable {
    case success(String)
    case failed(AISettingsError)
}

@MainActor
final class AISettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(AISettingsError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var snapshot: AISettingsSnapshot?
    @Published private(set) var saveError: AISettingsError?
    @Published private(set) var actionFeedback: AISettingsActionFeedback?
    @Published private(set) var isSaving = false

    let repoPath: String
    private let loader: any CoreAISettingsLoading
    private let updater: any CoreAISettingsUpdating
    private let errorMapper: any CoreErrorMapping
    private var savedSnapshot: AISettingsSnapshot?
    private var pendingSave: AISettingsConfigSnapshot?
    private var pendingPause: AISettingsConfigSnapshot?

    init(
        repoPath: String,
        loader: any CoreAISettingsLoading = CoreBridge(),
        updater: any CoreAISettingsUpdating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.errorMapper = errorMapper
    }

    var isLoaded: Bool { loadState == .loaded }
    var hasRetryableSave: Bool { pendingSave != nil && !isSaving }
    var hasRetryablePause: Bool { pendingPause != nil && !isSaving }

    func load() async {
        loadState = .loading
        saveError = nil
        actionFeedback = nil
        pendingSave = nil
        pendingPause = nil
        do {
            let loaded = try await loader.loadAISettings(repoPath: repoPath)
            snapshot = loaded
            savedSnapshot = loaded
            loadState = .loaded
        } catch {
            snapshot = nil
            savedSnapshot = nil
            loadState = .failed(await settingsError(
                for: error,
                message: "AI settings could not be loaded.",
                fallbackRecovery: "Retry"
            ))
        }
    }

    func setAIEnabled(_ enabled: Bool) async {
        guard var config = editableConfig(), config.aiEnabled != enabled else { return }
        config.aiEnabled = enabled
        await persist(config, failureMessage: "AI settings could not be saved.")
    }

    func setLocalAIEnabled(_ enabled: Bool) async {
        guard var config = editableConfig(), config.localAIEnabled != enabled else { return }
        config.localAIEnabled = enabled
        await persist(config, failureMessage: "AI settings could not be saved.")
    }

    func setProviderPreference(_ preference: AISettingsProviderPreference) async {
        guard var config = editableConfig(), config.providerPreference != preference else { return }
        if preference == .remoteFirst && !config.remoteAIAllowed {
            actionFeedback = .failed(AISettingsError(
                message: "Remote AI requires explicit setup.",
                recovery: "Use Configure remote AI before selecting Remote first.",
                detail: "S3-03 owns provider setup, API key storage, and connection verification."
            ))
            return
        }
        config.providerPreference = preference
        await persist(config, failureMessage: "AI settings could not be saved.")
    }

    func setFeature(_ feature: AISettingsFeatureKind, enabled: Bool) async {
        guard var config = editableConfig() else { return }
        config.setFeature(feature, enabled: enabled)
        await persist(config, failureMessage: "AI settings could not be saved.")
    }

    func disableRemoteAI() async {
        guard var config = editableConfig(), config.remoteAIAllowed else { return }
        config.remoteAIAllowed = false
        if config.providerPreference == .remoteFirst {
            config.providerPreference = .localFirst
        }
        await persist(config, failureMessage: "AI settings could not be saved.")
    }

    func pauseAllAI() async {
        guard var config = editableConfig(), config.aiEnabled else { return }
        config.aiEnabled = false
        await persist(config, failureMessage: "AI could not be paused.", restoreOnFailure: true)
    }

    func retrySave() async {
        guard let pendingSave else { return }
        await persist(pendingSave, failureMessage: "AI settings could not be saved.")
    }

    func retryPause() async {
        guard let pendingPause else { return }
        await persist(pendingPause, failureMessage: "AI could not be paused.", restoreOnFailure: true)
    }

    func revertChanges() {
        snapshot = savedSnapshot
        pendingSave = nil
        pendingPause = nil
        saveError = nil
        actionFeedback = nil
    }

    func openRemoteConfigurationEntry() {
        actionFeedback = .success("Remote AI configuration is handled by S3-03.")
    }

    func openLocalModelStatusEntry() {
        actionFeedback = .success("Local model status is handled by S3-02.")
    }

    func openPrivacyRulesEntry() {
        actionFeedback = .success("Privacy rules are handled by S3-09.")
    }

    func openCallLogEntry() {
        actionFeedback = .success("AI call log is handled by S3-05.")
    }

    private func editableConfig() -> AISettingsConfigSnapshot? {
        snapshot?.config.normalized()
    }

    private func persist(
        _ config: AISettingsConfigSnapshot,
        failureMessage: String,
        restoreOnFailure: Bool = false
    ) async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        actionFeedback = nil
        do {
            let updated = try await updater.updateAISettings(repoPath: repoPath, newConfig: config.normalized())
            snapshot = updated
            savedSnapshot = updated
            pendingSave = nil
            pendingPause = nil
            actionFeedback = restoreOnFailure ? .success("AI paused.") : nil
        } catch {
            let mapped = await settingsError(for: error, message: failureMessage, fallbackRecovery: "Retry save")
            if restoreOnFailure {
                snapshot = savedSnapshot
                pendingPause = config
            } else if let current = snapshot {
                snapshot = current.withPendingConfig(config)
                pendingSave = config
            }
            saveError = mapped
        }
        isSaving = false
    }

    private func settingsError(for error: Error, message: String, fallbackRecovery: String) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: message,
                recovery: mapping.suggestedAction.isEmpty ? fallbackRecovery : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }
}

struct BundleAppVersionReader: AppVersionReading {
    func appVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBuild = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedVersion.isEmpty { return "Unknown" }
        if trimmedBuild.isEmpty { return trimmedVersion }
        return "\(trimmedVersion) (\(trimmedBuild))"
    }
}

struct AdvancedSettingsLogFolderOpener: AdvancedSettingsLogFolderOpening {
    @MainActor
    func openLogsFolder(repoPath: String) throws -> String {
        let logsURL = Self.logsURL(repoPath: repoPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: logsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AdvancedSettingsLogFolderError.missing(logsURL.path)
        }
        guard NSWorkspace.shared.open(logsURL) else {
            throw AdvancedSettingsLogFolderError.openRejected(logsURL.path)
        }
        return logsURL.path
    }

    static func logsURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }
}

struct AdvancedSettingsDiagnosticCopier: AdvancedSettingsDiagnosticSummaryCopying {
    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(summary, forType: .string) else {
            throw AdvancedSettingsDiagnosticSummaryError.copyRejected
        }
    }
}

enum AdvancedSettingsLogFolderError: Error, Equatable, LocalizedError {
    case missing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case let .missing(path):
            "Logs folder is missing: \(path)"
        case let .openRejected(path):
            "Finder rejected opening logs folder: \(path)"
        }
    }
}

enum AdvancedSettingsDiagnosticSummaryError: Error, Equatable, LocalizedError {
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .copyRejected:
            "Pasteboard rejected the diagnostic summary."
        }
    }
}
