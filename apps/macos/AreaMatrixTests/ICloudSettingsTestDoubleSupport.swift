@testable import AreaMatrix
import Foundation
import XCTest

struct StaticICloudStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    init(snapshot: IntegrationsICloudSnapshot = .testFixture()) {
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
    private var openCount = 0

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openICloudHelp() throws {
        openCount += 1
        try result.get()
    }

    func assertOpenCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openCount, expectedCount, file: file, line: line)
    }
}
