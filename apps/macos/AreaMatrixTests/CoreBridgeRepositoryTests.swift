import Foundation
import XCTest
@testable import AreaMatrix

final class CoreBridgeRepositoryTests: XCTestCase {
    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughDefaultCoreBridge() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)

        let model = OnboardingModel(
            settingsReader: CoreBridgeTestSettingsReader(repoPath: repoURL.path),
            helpOpener: CoreBridgeTestHelpOpener()
        )

        await model.bootstrapIfNeeded()

        let expectedConfig = RepoConfigSnapshot(
            repoPath: repoURL.path,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )

        guard case .mainEmpty(let opening) = model.route else {
            return XCTFail("expected main empty route, got \(model.route)")
        }
        XCTAssertEqual(opening.config, expectedConfig)
        XCTAssertTrue(opening.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
    }

    func testCoreBridgePropagatesRealConfigError() async throws {
        do {
            _ = try await CoreBridge().loadConfig(repoPath: "")
            XCTFail("expected CoreError.Config")
        } catch let error as CoreError {
            guard case .Config = error else {
                return XCTFail("expected Config, got \(error)")
            }
        }
    }

    func testCoreBridgeValidatesTemporaryRepoPathWithoutCreatingMetadata() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        let validation = try await CoreBridge().validateRepoPath(repoPath: repoURL.path)

        XCTAssertEqual(validation.repoPath, repoURL.path)
        XCTAssertTrue(validation.exists)
        XCTAssertTrue(validation.isDirectory)
        XCTAssertFalse(validation.isInsideAreaMatrix)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
    }

    func testCoreBridgeValidateInitializedRepoPathRequiresInitializedMetadata() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        do {
            _ = try await CoreBridge().validateInitializedRepoPath(repoPath: repoURL.path)
            XCTFail("expected RepoNotInitialized")
        } catch let error as CoreError {
            guard case .RepoNotInitialized = error else {
                return XCTFail("expected RepoNotInitialized, got \(error)")
            }
        }
    }
}

private func makeTemporaryRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixCoreBridgeRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct CoreBridgeTestSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private struct CoreBridgeTestHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}
