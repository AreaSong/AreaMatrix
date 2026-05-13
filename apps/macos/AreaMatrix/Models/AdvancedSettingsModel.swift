import Combine
import Foundation

enum AdvancedSettingsOverviewOutput: String, CaseIterable, Equatable, Identifiable {
    case generatedOnly
    case rootAreaMatrixFile

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        self = snapshotValue == "RootAreaMatrixFile" ? .rootAreaMatrixFile : .generatedOnly
    }

    var snapshotValue: String {
        switch self {
        case .generatedOnly:
            "GeneratedOnly"
        case .rootAreaMatrixFile:
            "RootAreaMatrixFile"
        }
    }

    var label: String {
        switch self {
        case .generatedOnly:
            "Generated only"
        case .rootAreaMatrixFile:
            "Root AREAMATRIX.md"
        }
    }
}

enum AdvancedSettingsSaveKind: Equatable {
    case overview
    case replace

    var message: String {
        switch self {
        case .overview:
            "Could not save overview setting"
        case .replace:
            "Could not save advanced setting"
        }
    }
}

struct AdvancedSettingsError: Equatable {
    var message: String
    var recovery: String
}

enum AdvancedSettingsAccessibilityID {
    static let overviewOutput = "S1-30-C1-20-overview-output"
    static let overviewRetrySave = "S1-30-C1-20-retry-save"
    static let replaceRetrySave = "S1-30-C1-04-retry-save"
    static let genericRetrySave = "S1-30-retry-save"
}

struct AdvancedSettingsDraft: Equatable {
    var overviewOutput: AdvancedSettingsOverviewOutput
    var allowReplaceDuringImport: Bool

    init(config: RepoConfigSnapshot) {
        overviewOutput = AdvancedSettingsOverviewOutput(snapshotValue: config.overviewOutput)
        allowReplaceDuringImport = config.allowReplaceDuringImport
    }
}

private struct AdvancedSettingsPendingSave: Equatable {
    var config: RepoConfigSnapshot
    var kind: AdvancedSettingsSaveKind
}

@MainActor
final class AdvancedSettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(AdvancedSettingsError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var draft: AdvancedSettingsDraft?
    @Published private(set) var savedConfig: RepoConfigSnapshot?
    @Published private(set) var saveError: AdvancedSettingsError?
    @Published private(set) var pendingRootOverviewStatus: RootOverviewFileStatus?
    @Published private(set) var isReplaceConfirmationPending = false
    @Published private(set) var isSaving = false
    @Published private(set) var versionInfo = AdvancedSettingsVersionInfo.unknown
    @Published private(set) var versionError: AdvancedSettingsError?
    @Published private(set) var diagnosticsState: AdvancedSettingsDiagnosticsState = .idle
    @Published private(set) var actionFeedback: AdvancedSettingsActionFeedback?

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let rootOverviewInspector: any RootOverviewFileInspecting
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let appVersionReader: any AppVersionReading
    private let coreVersionReader: any CoreVersionReading
    private let metadataReader: any ExistingRepositoryMetadataReading
    private let logsOpener: any AdvancedSettingsLogFolderOpening
    private let summaryCopier: any AdvancedSettingsDiagnosticSummaryCopying
    private let errorMapper: any CoreErrorMapping
    private var pendingRetry: AdvancedSettingsPendingSave?

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        rootOverviewInspector: any RootOverviewFileInspecting = LocalRootOverviewFileInspector(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        appVersionReader: any AppVersionReading = BundleAppVersionReader(),
        coreVersionReader: any CoreVersionReading = CoreBridge(),
        metadataReader: any ExistingRepositoryMetadataReading = SQLiteExistingRepositoryMetadataReader(),
        logsOpener: any AdvancedSettingsLogFolderOpening = AdvancedSettingsLogFolderOpener(),
        summaryCopier: any AdvancedSettingsDiagnosticSummaryCopying =
            AdvancedSettingsDiagnosticCopier(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.rootOverviewInspector = rootOverviewInspector
        self.diagnosticsCollector = diagnosticsCollector
        self.appVersionReader = appVersionReader
        self.coreVersionReader = coreVersionReader
        self.metadataReader = metadataReader
        self.logsOpener = logsOpener
        self.summaryCopier = summaryCopier
        self.errorMapper = errorMapper
    }

    var isLoaded: Bool {
        loadState == .loaded
    }

    var hasRetryableSave: Bool {
        pendingRetry != nil && !isSaving
    }

    var retrySaveAccessibilityIdentifier: String {
        guard let pendingRetry else { return AdvancedSettingsAccessibilityID.genericRetrySave }
        switch pendingRetry.kind {
        case .overview:
            return AdvancedSettingsAccessibilityID.overviewRetrySave
        case .replace:
            return AdvancedSettingsAccessibilityID.replaceRetrySave
        }
    }

    var writesDisabled: Bool {
        isSaving || !isLoaded || pendingRootOverviewStatus != nil || isReplaceConfirmationPending
    }

    func load() async {
        loadState = .loading
        saveError = nil
        pendingRetry = nil
        pendingRootOverviewStatus = nil
        isReplaceConfirmationPending = false
        diagnosticsState = .idle
        actionFeedback = nil
        versionError = nil
        versionInfo = AdvancedSettingsVersionInfo(
            appVersion: appVersionReader.appVersion(),
            coreVersion: "Unknown",
            repoSchemaVersion: nil
        )

        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
                .withAdvancedRepositoryPath(repoPath)
            savedConfig = config
            draft = AdvancedSettingsDraft(config: config)
            loadState = .loaded
            await refreshVersionInfo()
        } catch {
            savedConfig = nil
            draft = nil
            loadState = await .failed(mappedError(for: error, fallbackMessage: "Unable to load advanced settings"))
        }
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
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            diagnosticsState = .collected(snapshot)
        } catch {
            diagnosticsState = await .failed(mappedError(
                for: error,
                fallbackMessage: "Diagnostics could not be exported"
            ))
        }
    }

    func openLogsFolder() {
        actionFeedback = nil
        do {
            let openedPath = try logsOpener.openLogsFolder(repoPath: repoPath)
            actionFeedback = .success("Logs folder opened: \(openedPath)")
        } catch {
            actionFeedback = .failed(AdvancedSettingsError(
                message: "Open logs folder failed",
                recovery: "Check that .areamatrix/logs exists, then retry after Core logging is initialized."
            ))
        }
    }

    func copyDiagnosticSummary() {
        actionFeedback = nil
        do {
            try summaryCopier.copyDiagnosticSummary(diagnosticSummary())
            actionFeedback = .success("Diagnostic summary copied.")
        } catch {
            actionFeedback = .failed(AdvancedSettingsError(
                message: "Diagnostic summary could not be copied",
                recovery: "Copy the version and repository rows manually after checking clipboard permission."
            ))
        }
    }

    func requestOverviewOutput(_ output: AdvancedSettingsOverviewOutput) async {
        guard !isSaving, let savedConfig, output != draft?.overviewOutput else {
            return
        }

        if output == .rootAreaMatrixFile {
            pendingRootOverviewStatus = rootOverviewInspector.status(repoPath: repoPath)
            return
        }

        await persist(
            updating: savedConfig.withAdvancedOverviewOutput(output.snapshotValue),
            kind: .overview
        )
    }

    func confirmRootOverview() async {
        guard pendingRootOverviewStatus?.canEnableRootOverview == true, let savedConfig else {
            return
        }

        pendingRootOverviewStatus = nil
        await persist(
            updating: savedConfig.withAdvancedOverviewOutput(
                AdvancedSettingsOverviewOutput.rootAreaMatrixFile.snapshotValue
            ),
            kind: .overview
        )
    }

    func cancelRootOverview() {
        pendingRootOverviewStatus = nil
        restoreDraftFromSavedConfig()
    }

    func requestAllowReplaceDuringImport(_ isEnabled: Bool) async {
        guard !isSaving, let savedConfig, isEnabled != draft?.allowReplaceDuringImport else {
            return
        }

        if isEnabled {
            isReplaceConfirmationPending = true
            return
        }

        await persist(updating: savedConfig.withAdvancedAllowReplaceDuringImport(false), kind: .replace)
    }

    func confirmAllowReplaceDuringImport() async {
        guard let savedConfig else {
            return
        }

        isReplaceConfirmationPending = false
        await persist(updating: savedConfig.withAdvancedAllowReplaceDuringImport(true), kind: .replace)
    }

    func cancelAllowReplaceDuringImport() {
        isReplaceConfirmationPending = false
        restoreDraftFromSavedConfig()
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else {
            return
        }

        await persist(updating: pendingRetry.config, kind: pendingRetry.kind)
    }

    private func persist(updating config: RepoConfigSnapshot, kind: AdvancedSettingsSaveKind) async {
        isSaving = true
        saveError = nil
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: config)
            savedConfig = config
            draft = AdvancedSettingsDraft(config: config)
            pendingRetry = nil
        } catch {
            restoreDraftFromSavedConfig()
            saveError = await mappedError(for: error, fallbackMessage: kind.message)
            pendingRetry = AdvancedSettingsPendingSave(config: config, kind: kind)
        }
        isSaving = false
    }

    private func restoreDraftFromSavedConfig() {
        if let savedConfig {
            draft = AdvancedSettingsDraft(config: savedConfig)
        }
    }

    private func refreshVersionInfo() async {
        var info = AdvancedSettingsVersionInfo(
            appVersion: appVersionReader.appVersion(),
            coreVersion: "Unknown",
            repoSchemaVersion: nil
        )
        var failures: [AdvancedSettingsError] = []

        do {
            info.coreVersion = try await coreVersionReader.coreVersion()
        } catch {
            await failures.append(mappedError(for: error, fallbackMessage: "Core version unavailable"))
        }

        do {
            info.repoSchemaVersion = try await metadataReader.metadata(repoPath: repoPath).schemaVersion
        } catch {
            await failures.append(mappedError(for: error, fallbackMessage: "Repo schema version unavailable"))
        }

        versionInfo = info
        versionError = Self.combinedVersionError(failures)
    }

    private func mappedError(for error: Error, fallbackMessage: String) async -> AdvancedSettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AdvancedSettingsError(
                message: fallbackMessage,
                recovery: mapping.suggestedAction.isEmpty ? mapping.userMessage : mapping.suggestedAction
            )
        }

        return AdvancedSettingsError(message: fallbackMessage, recovery: error.localizedDescription)
    }

    private static func combinedVersionError(_ failures: [AdvancedSettingsError]) -> AdvancedSettingsError? {
        guard let first = failures.first else { return nil }
        guard failures.count > 1 else { return first }

        return AdvancedSettingsError(
            message: "Some diagnostics values are unavailable",
            recovery: failures.map(\.message).joined(separator: "; ")
        )
    }

    private func diagnosticSummary() -> String {
        let schema = versionInfo.repoSchemaVersionLabel
        let overview = draft?.overviewOutput.snapshotValue ?? "Unknown"
        let replace = draft?.allowReplaceDuringImport == true ? "true" : "false"
        let repoName = URL(fileURLWithPath: repoPath, isDirectory: true).lastPathComponent
        return """
        AreaMatrix diagnostic summary
        Repository: \(repoName.isEmpty ? "Unknown" : repoName)
        App version: \(versionInfo.appVersion)
        Core version: \(versionInfo.coreVersion)
        Repo schema version: \(schema)
        Overview output: \(overview)
        Allow replace during import: \(replace)
        Diagnostics exclude original file contents and are not uploaded automatically.
        """
    }
}

extension RepoConfigSnapshot {
    func withAdvancedRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withAdvancedOverviewOutput(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.overviewOutput = value
        return config
    }

    func withAdvancedAllowReplaceDuringImport(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.allowReplaceDuringImport = value
        return config
    }
}
