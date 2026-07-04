@testable import AreaMatrix
import Foundation

struct StaticICloudStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    init(snapshot: IntegrationsICloudSnapshot = IntegrationsICloudSnapshot(
        repositoryLocation: .localFolder,
        iCloudStatus: .unavailable
    )) {
        self.snapshot = snapshot
    }

    func snapshot(repoPath _: String, config _: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        snapshot
    }
}

struct StaticICloudIdentityTokenReader: ICloudIdentityTokenReading {
    var hasICloudIdentityToken: Bool
}

struct StaticICloudResourceValueReader: ICloudResourceValueReading {
    var isUbiquitousItem: Bool?

    func isUbiquitousItem(at _: URL) throws -> Bool? {
        isUbiquitousItem
    }
}

struct NoopICloudHelpOpener: ICloudHelpOpening {
    @MainActor
    func openICloudHelp() throws {}
}

@MainActor
final class RecordingICloudHelpOpener: ICloudHelpOpening {
    private let result: Result<Void, Error>
    private(set) var openCount = 0

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openICloudHelp() throws {
        openCount += 1
        try result.get()
    }
}
