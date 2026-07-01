@testable import AreaMatrix

struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    var lastOpenedAtByRepoPath: [String: Int64] = [:]

    func configuredRepoPath() -> String? {
        repoPath
    }

    func lastSuccessfulRepoOpenAt(repoPath: String) -> Int64? {
        lastOpenedAtByRepoPath[repoPath]
    }
}

final class RecordingAppSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []
    private(set) var successfulRepoOpens: [(repoPath: String, openedAt: Int64)] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }

    func saveSuccessfulRepoOpen(repoPath: String, openedAt: Int64) {
        successfulRepoOpens.append((repoPath: repoPath, openedAt: openedAt))
    }
}
