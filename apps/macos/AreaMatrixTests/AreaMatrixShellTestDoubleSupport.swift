@testable import AreaMatrix
import XCTest

typealias ShellStaticSettingsReader = StaticSettingsReader

typealias ShellRecordingSettingsWriter = RecordingAppSettingsWriter

typealias ShellRecordingConfigLoader = RecordingConfigurationLoader

typealias ShellRecordingRepositoryOpener = RecordingRepositoryOpener

typealias ShellRecordingPathValidator = RecordingRepositoryPathValidator

typealias ShellRecordingInitializedPathValidator = RecordingRepositoryPathValidator

typealias ShellRecordingExternalChangesSyncer = RecordingExternalChangesSyncer

typealias ShellRecordingDiagnosticsCollector = RecordingDiagnosticsCollector

struct ShellFailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

@MainActor
final class ShellRecordingPathCopier: RepositoryPathCopying {
    private(set) var requests: [(repoPath: String, relativePath: String)] = []
    private(set) var multiPathRequests: [(repoPath: String, relativePaths: [String])] = []

    func copyPath(repoPath: String, relativePath: String) throws {
        requests.append((repoPath: repoPath, relativePath: relativePath))
    }

    func copyPaths(repoPath: String, relativePaths: [String]) throws {
        multiPathRequests.append((repoPath: repoPath, relativePaths: relativePaths))
    }
}

typealias ShellExistingRepoMetadataReader = StaticExistingRepositoryMetadataReader

@MainActor
final class ShellRecordingDirectoryPicker: RepositoryDirectoryPicking {
    private let selectedURL: URL?
    private(set) var chooseCount = 0

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func chooseDirectory() -> URL? {
        chooseCount += 1
        return selectedURL
    }
}
