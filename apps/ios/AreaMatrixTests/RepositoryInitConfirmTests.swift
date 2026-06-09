@testable import AreaMatrixIOS
import XCTest

@MainActor
final class RepositoryInitConfirmTests: XCTestCase {
    func testRefreshRerunsReadOnlyValidationWithoutWriting() async throws {
        let url = URL(fileURLWithPath: "/tmp/EmptyRepo")
        let bridge = FakeMobileRepositoryCoreBridge(validations: [
            .emptyDirectory(path: url.path),
            .emptyDirectory(path: url.path)
        ])
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)
        let candidate = try XCTUnwrap(repositoryInitCandidate(from: model.route))

        await model.refreshRepositoryInitConfirmation(candidate)

        XCTAssertEqual(bridge.validatedPaths, [url.path, url.path])
        XCTAssertTrue(bridge.initializedPaths.isEmpty)
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
        XCTAssertEqual(repositoryInitCandidate(from: model.route)?.validation.repoPath, url.path)
        XCTAssertNil(model.error)
    }

    func testCreateRepositoryInitializesAndOpensLibrary() async throws {
        let url = URL(fileURLWithPath: "/tmp/EmptyRepo")
        let bridge = FakeMobileRepositoryCoreBridge(validations: [
            .emptyDirectory(path: url.path),
            .emptyDirectory(path: url.path),
            .initialized(path: url.path)
        ])
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(
            bridge: bridge,
            accessService: access,
            now: { Date(timeIntervalSince1970: 84) }
        )

        await model.connectSelectedURL(url)
        let candidate = try XCTUnwrap(repositoryInitCandidate(from: model.route))

        await model.createRepository(from: candidate)

        XCTAssertEqual(bridge.validatedPaths, [url.path, url.path, url.path])
        XCTAssertEqual(bridge.initializedPaths, [url.path])
        XCTAssertEqual(bridge.loadedConfigPaths, [url.path])
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertEqual(persistedPaths, [url.path])
        guard case let .mobileLibrary(connection) = model.route else {
            return XCTFail("expected initialized repository to open")
        }
        XCTAssertTrue(connection.validation.isInitialized)
        XCTAssertEqual(connection.config.repoPath, url.path)
        XCTAssertNil(model.error)
    }

    func testCreateRepositoryFailureStaysOnInitConfirmationWithoutSavingBookmark() async throws {
        let url = URL(fileURLWithPath: "/tmp/EmptyRepo")
        let bridge = FakeMobileRepositoryCoreBridge(
            validations: [.emptyDirectory(path: url.path), .emptyDirectory(path: url.path)],
            initializeError: .permissionDenied(url.path)
        )
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)
        let candidate = try XCTUnwrap(repositoryInitCandidate(from: model.route))

        await model.createRepository(from: candidate)

        XCTAssertEqual(bridge.initializedPaths, [url.path])
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
        XCTAssertEqual(model.error, .permissionDenied(url.path))
        XCTAssertEqual(repositoryInitCandidate(from: model.route)?.validation.repoPath, url.path)
    }

    func testContentMatchesPageSpecAndSafetyRules() {
        let path = "/tmp/Mobile Documents/AreaMatrixRepo"
        let content = RepositoryInitConfirmContent(candidate: candidate(
            path: path,
            validation: .emptyDirectory(path: path)
        ))

        XCTAssertEqual(content.title, "Create AreaMatrix Repository")
        XCTAssertEqual(content.folderPath, path)
        XCTAssertEqual(content.pathType, "iCloud Drive")
        XCTAssertEqual(content.writableText, "Yes")
        XCTAssertTrue(content.safetyText.contains(".areamatrix"))
        XCTAssertTrue(content.noOverwriteText.contains("No existing files"))
        XCTAssertTrue(content.canCreate)
        XCTAssertNil(content.disabledReason)
        XCTAssertTrue(content.checklistItems.contains { item in
            item.title == "Folder is empty" && item.status == .passed
        })
        XCTAssertTrue(content.checklistItems.contains { item in
            item.title == "Write permission available" && item.status == .passed
        })
        XCTAssertNotNil(content.riskText)
    }

    func testContentBlocksNonEmptyOrUnwritableFolders() {
        let nonEmpty = RepositoryInitConfirmContent(candidate: candidate(
            path: "/tmp/Existing",
            validation: .nonEmptyDirectory(path: "/tmp/Existing")
        ))
        let unwritable = RepositoryInitConfirmContent(candidate: candidate(
            path: "/tmp/ReadOnly",
            validation: .fixture(
                path: "/tmp/ReadOnly",
                isWritable: false,
                isEmpty: true,
                isInitialized: false,
                recommendedMode: .createEmpty,
                issues: [.notWritable]
            )
        ))

        XCTAssertFalse(nonEmpty.canCreate)
        XCTAssertEqual(nonEmpty.disabledReason, "This folder is not eligible for empty repository creation.")
        XCTAssertFalse(unwritable.canCreate)
        XCTAssertEqual(unwritable.disabledReason, "AreaMatrix cannot write metadata in this folder.")
    }

    private func repositoryInitCandidate(
        from route: MobileRepositoryConnectionRoute?
    ) -> MobileRepositoryCandidate? {
        guard case let .repositoryInitConfirm(candidate) = route else {
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
