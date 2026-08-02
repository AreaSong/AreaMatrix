@testable import AreaMatrix
import XCTest

final class AboutSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadShowsAppCoreAndSchemaVersionsThroughDeclaredReaders() async {
        let coreReader = StaticCoreVersionReader(result: .success("0.1.0"))
        let metadataReader = StaticExistingRepositoryMetadataReader(schemaVersion: 1)
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.2.3 (45)"),
            coreVersionReader: coreReader,
            metadataReader: metadataReader,
            externalLinkOpener: RecordingAboutExternalLinkOpener(),
            stringCopier: RecordingAboutStringCopier(),
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo, AboutSettingsVersionInfo(
            appVersion: "1.2.3 (45)",
            coreVersion: "0.1.0",
            schemaVersion: "v1"
        ))
        XCTAssertNil(model.versionError)
        await coreReader.assertRequestCount(1)
        await metadataReader.assertRequestedPaths(["/tmp/repo"])
    }

    @MainActor
    func testSchemaFailureKeepsAboutPaneUsableAndPointsToUnifiedDiagnostics() async {
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.0"),
            coreVersionReader: StaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: StaticExistingRepositoryMetadataReader(result: .failure(CoreError.Db(message: "missing"))),
            externalLinkOpener: RecordingAboutExternalLinkOpener(),
            stringCopier: RecordingAboutStringCopier(),
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo.schemaVersion, L10n.string("Unknown"))
        XCTAssertEqual(model.versionError?.message, L10n.message("Schema version unavailable"))
        XCTAssertEqual(model.versionError?.recovery, L10n.message("Collect diagnostics..."))
    }

    @MainActor
    func testSchemaFailureDefaultsToBridgeErrorMappingAndKeepsAboutRecovery() async {
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.0"),
            coreVersionReader: StaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: StaticExistingRepositoryMetadataReader(result: .failure(CoreError.Db(message: "missing"))),
            externalLinkOpener: RecordingAboutExternalLinkOpener(),
            stringCopier: RecordingAboutStringCopier(),
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo.schemaVersion, L10n.string("Unknown"))
        XCTAssertEqual(model.versionError?.message, L10n.message("Schema version unavailable"))
        XCTAssertEqual(model.versionError?.recovery, L10n.message("Collect diagnostics..."))
    }

    @MainActor
    func testExternalLinkFailureStaysInMacLayerWithCopyableRecovery() {
        let copier = RecordingAboutStringCopier()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.0"),
            coreVersionReader: StaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: StaticExistingRepositoryMetadataReader(schemaVersion: 1),
            externalLinkOpener: RecordingAboutExternalLinkOpener { link in
                throw AboutSettingsPlatformError.openRejected(link.urlString)
            },
            stringCopier: copier,
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: announcer
        )

        model.openExternalLink(.github)
        let expectedError = AboutSettingsError(
            message: L10n.message(
                "settings.about.linkOpenFailed",
                arguments: [.string(AboutExternalLink.github.title)]
            ),
            recovery: L10n.message("Copy the URL and open it in your browser."),
            copyableDetail: AboutExternalLink.github.urlString
        )
        XCTAssertEqual(model.actionFeedback, .failed(expectedError))

        model.copyActionDetail(expectedError)

        copier.assertCopiedValues([AboutExternalLink.github.urlString])
        announcer.assertAnnouncementDescriptors([expectedError.message])
    }
}

private extension RecordingCoreErrorMapper {
    static func aboutSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            let message = switch error {
            case .Db:
                "Collect diagnostics..."
            default:
                "Retry."
            }
            return CoreErrorMappingSnapshot.testFixture(
                kind: .db,
                userMessage: message,
                severity: .medium,
                suggestedAction: message,
                recoverability: .retryable,
                rawContext: error.localizedDescription
            )
        }
    }
}
