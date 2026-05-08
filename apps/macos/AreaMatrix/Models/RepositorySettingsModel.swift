import Combine
import Foundation

struct RepositorySettingsLoadError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct RepositorySettingsSyncError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct RepositorySettingsSummary: Equatable, Sendable {
    var repositoryName: String
    var location: String
    var overviewMode: String
    var generatedPath: String
    var rootFile: String
    var readmePolicy: String

    init(config: RepoConfigSnapshot, fallbackRepoPath: String) {
        let resolvedPath = config.repoPath.isEmpty || config.repoPath != fallbackRepoPath
            ? fallbackRepoPath
            : config.repoPath
        repositoryName = Self.repositoryName(for: resolvedPath)
        location = resolvedPath
        overviewMode = Self.overviewModeLabel(for: config.overviewOutput)
        generatedPath = ".areamatrix/generated/root.md"
        rootFile = config.overviewOutput == "RootAreaMatrixFile" ? "AREAMATRIX.md" : "Off"
        readmePolicy = "User file, never managed by AreaMatrix"
    }

    private static func repositoryName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "AreaMatrix" : name
    }

    private static func overviewModeLabel(for value: String) -> String {
        value == "RootAreaMatrixFile" ? "Root AREAMATRIX.md enabled" : "Generated only"
    }
}

@MainActor
final class RepositorySettingsModel: ObservableObject {
    enum LoadState: Equatable, Sendable {
        case loading
        case loaded(RepositorySettingsSummary)
        case failed(RepositorySettingsLoadError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var loadedConfig: RepoConfigSnapshot?
    @Published private(set) var syncError: RepositorySettingsSyncError?

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.errorMapper = errorMapper
    }

    var isLoading: Bool {
        loadState == .loading
    }

    var summary: RepositorySettingsSummary? {
        guard case .loaded(let summary) = loadState else { return nil }
        return summary
    }

    var loadError: RepositorySettingsLoadError? {
        guard case .failed(let error) = loadState else { return nil }
        return error
    }

    func load() async {
        loadState = .loading
        syncError = nil
        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
            let effectiveConfig = config.withRepositoryPath(repoPath)
            loadedConfig = effectiveConfig

            if shouldSyncRepositoryPath(from: config) {
                do {
                    try await updater.updateConfig(repoPath: repoPath, newConfig: effectiveConfig)
                } catch {
                    syncError = await syncError(for: error)
                }
            }

            loadState = .loaded(RepositorySettingsSummary(config: effectiveConfig, fallbackRepoPath: repoPath))
        } catch {
            loadedConfig = nil
            loadState = .failed(await loadError(for: error))
        }
    }

    private func shouldSyncRepositoryPath(from config: RepoConfigSnapshot) -> Bool {
        repositoryMetadataDatabaseExists && config.repoPath != repoPath
    }

    private var repositoryMetadataDatabaseExists: Bool {
        let databaseURL = URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix/index.db", isDirectory: false)
        return FileManager.default.fileExists(atPath: databaseURL.path)
    }

    private func loadError(for error: Error) async -> RepositorySettingsLoadError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsLoadError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return RepositorySettingsLoadError(
            message: error.localizedDescription,
            recovery: "Retry status after the repository is available."
        )
    }

    private func syncError(for error: Error) async -> RepositorySettingsSyncError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsSyncError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return RepositorySettingsSyncError(
            message: error.localizedDescription,
            recovery: "Retry status after the repository can be written."
        )
    }
}

private extension RepoConfigSnapshot {
    func withRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }
}
