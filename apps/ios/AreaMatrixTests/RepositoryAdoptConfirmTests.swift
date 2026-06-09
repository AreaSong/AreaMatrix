@testable import AreaMatrixIOS
import XCTest

@MainActor
final class RepositoryAdoptConfirmTests: XCTestCase {
    func testRefreshRerunsReadOnlyValidationWithoutAdopting() async throws {
        let url = URL(fileURLWithPath: "/tmp/ExistingFolder")
        let bridge = FakeMobileRepositoryCoreBridge(validations: [
            .nonEmptyDirectory(path: url.path),
            .nonEmptyDirectory(path: url.path)
        ])
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)
        let candidate = try XCTUnwrap(repositoryAdoptCandidate(from: model.route))

        await model.refreshRepositoryAdoptConfirmation(candidate)

        XCTAssertEqual(bridge.validatedPaths, [url.path, url.path])
        XCTAssertTrue(bridge.adoptedPaths.isEmpty)
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
        XCTAssertEqual(repositoryAdoptCandidate(from: model.route)?.validation.repoPath, url.path)
        XCTAssertNil(model.error)
    }

    func testAdoptRepositoryInitializesAndOpensLibraryThroughCoreBridge() async throws {
        let url = URL(fileURLWithPath: "/tmp/ExistingFolder")
        let bridge = FakeMobileRepositoryCoreBridge(validations: [
            .nonEmptyDirectory(path: url.path),
            .nonEmptyDirectory(path: url.path),
            .initialized(path: url.path)
        ])
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(
            bridge: bridge,
            accessService: access,
            now: { Date(timeIntervalSince1970: 126) }
        )

        await model.connectSelectedURL(url)
        let candidate = try XCTUnwrap(repositoryAdoptCandidate(from: model.route))

        await model.adoptRepository(from: candidate)

        XCTAssertEqual(bridge.validatedPaths, [url.path, url.path, url.path])
        XCTAssertEqual(bridge.adoptedPaths, [url.path])
        XCTAssertEqual(bridge.initializedPaths, [])
        XCTAssertEqual(bridge.loadedConfigPaths, [url.path])
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertEqual(persistedPaths, [url.path])
        guard case let .mobileLibrary(connection) = model.route else {
            return XCTFail("expected adopted repository to open")
        }
        XCTAssertTrue(connection.validation.isInitialized)
        XCTAssertEqual(connection.config.repoPath, url.path)
        XCTAssertNil(model.error)
    }

    func testAdoptRepositoryFailureStaysOnAdoptConfirmationWithoutSavingBookmark() async throws {
        let url = URL(fileURLWithPath: "/tmp/ExistingFolder")
        let bridge = FakeMobileRepositoryCoreBridge(
            validations: [.nonEmptyDirectory(path: url.path), .nonEmptyDirectory(path: url.path)],
            adoptError: .permissionDenied(url.path)
        )
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)
        let candidate = try XCTUnwrap(repositoryAdoptCandidate(from: model.route))

        await model.adoptRepository(from: candidate)

        XCTAssertEqual(bridge.adoptedPaths, [url.path])
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
        XCTAssertEqual(model.error, .permissionDenied(url.path))
        XCTAssertEqual(repositoryAdoptCandidate(from: model.route)?.validation.repoPath, url.path)
    }

    func testContentMatchesPageSpecAndSafetyRules() {
        let path = "/tmp/Mobile Documents/ExistingFolder"
        let content = RepositoryAdoptConfirmContent(candidate: candidate(
            path: path,
            validation: .nonEmptyDirectory(path: path)
        ))

        XCTAssertEqual(content.title, "Use Existing Folder")
        XCTAssertEqual(content.folderPath, path)
        XCTAssertEqual(content.estimatedItemsText, "Non-empty folder")
        XCTAssertEqual(content.writableText, "Yes")
        XCTAssertEqual(content.locationTypeText, "iCloud Drive")
        XCTAssertTrue(content.metadataText.contains(".areamatrix"))
        XCTAssertTrue(content.noOverwriteText.contains("will not move"))
        XCTAssertTrue(content.rollbackText.contains("original files"))
        XCTAssertTrue(content.requiresHighRiskAcknowledgement)
        XCTAssertTrue(content.canAdopt)
        XCTAssertNil(content.disabledReason)
        XCTAssertTrue(content.checklistItems.contains { item in
            item.title == "Folder contains existing files" && item.status == .passed
        })
        XCTAssertTrue(content.checklistItems.contains { item in
            item.title == "Write permission available" && item.status == .passed
        })
    }

    func testContentBlocksEmptyUnwritableAndUnfinishedScanFolders() {
        let empty = RepositoryAdoptConfirmContent(candidate: candidate(
            path: "/tmp/Empty",
            validation: .emptyDirectory(path: "/tmp/Empty")
        ))
        let unwritable = RepositoryAdoptConfirmContent(candidate: candidate(
            path: "/tmp/ReadOnly",
            validation: .fixture(
                path: "/tmp/ReadOnly",
                isWritable: false,
                isEmpty: false,
                isInitialized: false,
                recommendedMode: .adoptExisting,
                issues: [.nonEmptyDirectory, .notWritable]
            )
        ))
        let unfinished = RepositoryAdoptConfirmContent(candidate: candidate(
            path: "/tmp/Unfinished",
            validation: .fixture(
                path: "/tmp/Unfinished",
                isEmpty: false,
                isInitialized: false,
                recommendedMode: .adoptExisting,
                issues: [.nonEmptyDirectory, .unfinishedScanSession]
            )
        ))

        XCTAssertFalse(empty.canAdopt)
        XCTAssertEqual(empty.disabledReason, "This folder is not eligible for existing folder adoption.")
        XCTAssertFalse(unwritable.canAdopt)
        XCTAssertEqual(unwritable.disabledReason, "AreaMatrix cannot write metadata in this folder.")
        XCTAssertFalse(unfinished.canAdopt)
        XCTAssertEqual(
            unfinished.disabledReason,
            "This folder has an unfinished scan session; recover it before adopting again."
        )
    }

    private func repositoryAdoptCandidate(
        from route: MobileRepositoryConnectionRoute?
    ) -> MobileRepositoryCandidate? {
        guard case let .repositoryAdoptConfirm(candidate) = route else {
            return nil
        }
        return candidate
    }

    private func candidate(path: String, validation: MobileRepositoryValidation) -> MobileRepositoryCandidate {
        MobileRepositoryCandidate(
            validation: validation,
            bookmark: RepositoryBookmark(
                url: URL(fileURLWithPath: path),
                displayName: "Repository",
                pathDisplay: path,
                lastOpenedAt: Date(timeIntervalSince1970: 0)
            )
        )
    }
}
