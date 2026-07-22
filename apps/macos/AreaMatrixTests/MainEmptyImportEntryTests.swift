@testable import AreaMatrix
import Foundation
import XCTest

final class MainEmptyImportEntryTests: XCTestCase {
    @MainActor
    func testMainEmptyImportButtonCreatesImportEntryFromPicker() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let fixture = makeMainEmptyImportEntryFixture(importURLs: [importURL])
        let opening = fixture.opening
        let model = fixture.model

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
        let fixture = makeMainEmptyImportEntryFixture()
        let opening = fixture.opening
        let model = fixture.model

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
        let fixture = makeMainEmptyImportEntryFixture()
        let opening = fixture.opening
        let model = fixture.model

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [firstURL, secondURL]
        )

        XCTAssertEqual(model.pendingImportEntry?.kind, .multipleItems(2))
        XCTAssertEqual(model.pendingImportEntry?.sheetTitle, "Import 2 files")
        XCTAssertEqual(model.pendingImportEntry?.source, .dropZone)
        XCTAssertEqual(model.pendingImportEntry?.urls, [firstURL, secondURL])
    }

    @MainActor
    func testMainEmptyImportEntryUsesInjectedTrashAvailability() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let fixture = makeMainEmptyImportEntryFixture(
            systemCapabilityChecker: StaticOnboardingSystemCapabilityChecker(isTrashAvailableValue: false)
        )
        let opening = fixture.opening
        let model = fixture.model

        model.startImportEntry(opening: opening, source: .dropZone, urls: [importURL])

        XCTAssertEqual(model.pendingImportEntry?.isTrashAvailable, false)
    }

    @MainActor
    func testMainEmptyDropEntryRejectsInvalidItemsWithAccessibleToast() throws {
        let fixture = makeMainEmptyImportEntryFixture()
        let opening = fixture.opening
        let model = fixture.model
        let accessibilityAnnouncer = fixture.accessibilityAnnouncer
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/a"))

        model.startImportEntry(opening: opening, source: .dropZone, urls: [remoteURL])

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.toastMessage, "Cannot import these items")
        accessibilityAnnouncer.assertAnnouncements(["Cannot import these items"])
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
