@testable import AreaMatrix
import Foundation
import XCTest

final class MainEmptyImportEntryTests: XCTestCase {
    @MainActor
    func testMainEmptyImportButtonCreatesImportEntryFromPicker() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener(),
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
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
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
    func testMainEmptyMultipleDropEntryCreatesBatchRequestForImportBatch() {
        let firstURL = URL(fileURLWithPath: "/tmp/a.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/b.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [firstURL, secondURL]
        )

        XCTAssertEqual(model.pendingImportEntry?.kind, .multipleItems(2))
        XCTAssertEqual(model.pendingImportEntry?.sheetTitle, "导入 2 个文件")
        XCTAssertEqual(model.pendingImportEntry?.source, .dropZone)
        XCTAssertEqual(model.pendingImportEntry?.urls, [firstURL, secondURL])
    }

    @MainActor
    func testMainEmptyImportEntryUsesInjectedTrashAvailability() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            systemCapabilityChecker: StaticOnboardingSystemCapabilityChecker(isTrashAvailableValue: false),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.startImportEntry(opening: opening, source: .dropZone, urls: [importURL])

        XCTAssertEqual(model.pendingImportEntry?.isTrashAvailable, false)
    }

    @MainActor
    func testMainEmptyDropEntryRejectsInvalidItemsWithAccessibleToast() throws {
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let accessibilityAnnouncer = MainEmptyImportAnnouncer()
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/a"))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: accessibilityAnnouncer,
            helpOpener: NoopWelcomeHelpOpener()
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
