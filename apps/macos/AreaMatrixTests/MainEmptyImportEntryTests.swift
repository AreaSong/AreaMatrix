import Foundation
import XCTest
@testable import AreaMatrix

final class MainEmptyImportEntryTests: XCTestCase {
    @MainActor
    func testMainEmptyImportButtonCreatesImportEntryFromPicker() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportRecordingAccessibilityAnnouncer(),
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener(),
            importPicker: MainEmptyImportStaticImportPicker(urls: [importURL])
        )

        model.chooseImportSources(opening: opening)

        XCTAssertEqual(model.pendingImportEntry?.repoPath, "/tmp/empty-repo")
        XCTAssertEqual(model.pendingImportEntry?.source, .filePicker)
        XCTAssertEqual(model.pendingImportEntry?.destination, .autoClassify)
        XCTAssertEqual(model.pendingImportEntry?.urls, [importURL])
        XCTAssertEqual(model.pendingImportEntry?.kind, .singleFile)
    }

    @MainActor
    func testMainEmptyDropEntryKeepsSidebarDestination() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportRecordingAccessibilityAnnouncer(),
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener()
        )

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [importURL],
            destination: .category("finance")
        )

        XCTAssertEqual(model.pendingImportEntry?.destination, .category("finance"))
        XCTAssertEqual(model.pendingImportEntry?.destinationLabel, "finance")
    }

    @MainActor
    func testMainEmptyDropEntryRejectsInvalidItemsWithAccessibleToast() throws {
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let accessibilityAnnouncer = MainEmptyImportRecordingAccessibilityAnnouncer()
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/a"))
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: accessibilityAnnouncer,
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener()
        )

        model.startImportEntry(opening: opening, source: .dropZone, urls: [remoteURL])

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.toastMessage, "Cannot import these items")
        XCTAssertEqual(accessibilityAnnouncer.announcements, ["Cannot import these items"])
    }

    func testDropFileURLItemDecoderAcceptsFileURLDataAndRejectsRemoteURL() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/source.pdf"))

        let decodedFileURL = FileDropAdapter.fileURL(from: fileURL.dataRepresentation as NSData)
        let decodedRemoteURL = FileDropAdapter.fileURL(from: remoteURL.dataRepresentation as NSData)

        XCTAssertEqual(decodedFileURL, fileURL)
        XCTAssertNil(decodedRemoteURL)
    }
}

private struct MainEmptyImportStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private struct MainEmptyImportNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private struct MainEmptyImportStaticImportPicker: RepositoryImportPicking {
    let urls: [URL]?

    @MainActor
    func chooseImportURLs() -> [URL]? { urls }
}

@MainActor
private final class MainEmptyImportRecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

private extension RepositoryOpeningResult {
    static func mainEmptyImportFixture(repoPath: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(slug: "__root__", displayName: "资料库", fileCount: 0, children: []),
            currentCategoryFiles: []
        )
    }
}
