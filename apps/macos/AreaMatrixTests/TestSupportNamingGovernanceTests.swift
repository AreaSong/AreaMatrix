import XCTest

final class TestSupportNamingGovernanceTests: XCTestCase {
    func testFixtureDataUsesFixturesFileSuffix() throws {
        let fixtureSupportSuffix = "Fixture" + "Support.swift"
        let testFixturesSuffix = "Test" + "Fixtures.swift"

        let violations = try testSupportSwiftFiles()
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(fixtureSupportSuffix) || $0.hasSuffix(testFixturesSuffix) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Pure fixture data belongs in *Fixtures.swift; behavior helpers belong in *TestSupport.swift."
        )
    }

    func testFixturesFilesDoNotContainBehaviorSupport() throws {
        let prohibitedTerms = [
            "Recording",
            "Recorder",
            "Recorded",
            "Spy",
            "Mock",
            "Stub",
            "Fake",
            "Noop",
            "Immediate",
            "CoreBridge",
            "Store",
            "Manager",
            "Service",
            "Actor",
            "@MainActor",
            "async",
            "throws",
            "FileManager",
            "temporaryDirectory",
            "createDirectory",
            "write("
        ]
        let violations = try testSupportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("Fixtures.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: prohibitedTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Fixture files should only define reusable sample data; behavior belongs in *TestSupport.swift."
        )
    }

    func testCoreBridgeUsageStaysInNamedBoundarySupportFiles() throws {
        let violations = try supportSwiftFiles()
            .filter { !isNamedCoreBridgeBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: ["CoreBridge"]) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Support files that touch CoreBridge must expose that bridge boundary in their file name."
        )
    }

    func testFileSystemIOStaysInNamedBoundarySupportFiles() throws {
        let fileSystemTerms = [
            "makeTestTemporaryDirectory",
            "FileManager",
            "temporaryDirectory",
            "createDirectory",
            "write(",
            "setAttributes",
            "removeItem",
            "copyItem",
            "moveItem"
        ]
        let violations = try supportSwiftFiles()
            .filter { !isNamedFileSystemBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: fileSystemTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Support files that perform filesystem IO must expose that boundary in their file name."
        )
    }

    func testBridgeBoundarySupportDoesNotHideFileSystemHelpers() throws {
        let fileSystemHelperTerms = [
            "makeTestTemporaryDirectory",
            "FileManager",
            "String(contentsOf:",
            "Data(contentsOf:",
            "createDirectory",
            "write(",
            "removeItem",
            "copyItem",
            "moveItem"
        ]
        let violations = try supportSwiftFiles()
            .filter { isNamedBridgeBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: fileSystemHelperTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Bridge support files should not hide filesystem helpers; use *FileSystemTestSupport.swift."
        )
    }

    func testTestDoubleSupportDoesNotHideBridgeOrFileSystemBoundaries() throws {
        let boundaryTerms = [
            "CoreBridge",
            "makeTestTemporaryDirectory",
            "FileManager",
            "temporaryDirectory",
            "String(contentsOf:",
            "Data(contentsOf:",
            "createDirectory",
            "write(",
            "setAttributes",
            "removeItem",
            "copyItem",
            "moveItem"
        ]
        let violations = try supportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: boundaryTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Test-double support files should stay pure doubles; use named bridge or filesystem boundary support files."
        )
    }

    func testRawTemporaryFilesystemOperationsStayInSharedSupport() throws {
        let temporaryDirectoryTerm = "FileManager.default." + "temporaryDirectory"
        let instanceTemporaryDirectoryTerm = ".temporary" + "Directory"
        let nsTemporaryDirectoryTerm = "NSTemporary" + "Directory("
        let removeItemTerm = "remove" + "Item(at:"
        let guardedTerms = [
            temporaryDirectoryTerm,
            instanceTemporaryDirectoryTerm,
            nsTemporaryDirectoryTerm,
            removeItemTerm
        ]
        let violations = try testSupportSwiftFiles()
            .filter { $0.lastPathComponent != "TestTemporaryDirectoryFileSystemTestSupport.swift" }
            .flatMap { try sourceTermViolations(in: $0, terms: guardedTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Raw temporary-directory creation and cleanup should stay behind " +
                "TestTemporaryDirectoryFileSystemTestSupport so tests share one filesystem safety boundary."
        )
    }

    func testActionRecordingSupportUsesTestDoubleSuffix() throws {
        let violations = try supportSwiftFiles()
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix("ActionRecordingTestSupport.swift") }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Action recording helpers are pure test doubles; use *ActionTestDoubleSupport.swift."
        )
    }

    func testStoreDoubleDeclarationsUseTestDoubleSuffix() throws {
        let storeDoubleDeclarations = [
            "actor StaticImportBatchSessionStore",
            "actor RecordingImportBatchSessionStore",
            "actor NoopUndoActionStore",
            "actor UndoActionRecordingTestStore",
            "actor LenientUndoActionRecordingTestStore",
            "actor RedoActionLogRecordingRedoStore",
            "actor DetailTagRecordingStore",
            "actor TagFilterForbiddenTagStore",
            "final class RemoteProviderTestCredentialStore"
        ]
        let violations = try supportSwiftFiles()
            .filter { !$0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: storeDoubleDeclarations) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Store double declarations should live in *TestDoubleSupport.swift."
        )
    }

    func testStoreDoubleAliasesUseTestDoubleSuffix() throws {
        let storeDoubleAliases = [
            "= LenientUndoActionRecordingTestStore",
            "= NoopUndoActionStore",
            "= RecordingSavedSearchStore"
        ]
        let violations = try supportSwiftFiles()
            .filter { !$0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: storeDoubleAliases) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Pure store double aliases should live in *TestDoubleSupport.swift."
        )
    }

    func testFeatureLocalDoublesUseTestDoubleSuffix() throws {
        let violations = try supportSwiftFiles()
            .filter { !$0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: featureLocalDoubleDeclarations) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature-local doubles should live in *TestDoubleSupport.swift."
        )
    }

    func testBridgeBoundaryDeclarationsUseBridgeSupportSuffix() throws {
        let violations = try supportSwiftFiles()
            .filter { !isNamedBridgeBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: bridgeBoundaryDeclarations) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Bridge protocol doubles should live in *BridgeTestSupport.swift."
        )
    }

    func testSnapshotDirectConstructorsStayInventoried() throws {
        for (term, inventory) in snapshotConstructorInventories {
            let actual = try countedTermMatches(in: testSupportSwiftFiles(), term: term)
            XCTAssertEqual(
                actual,
                inventory,
                "Snapshot test data should use shared testFixture helpers, except for inventoried roots."
            )
        }
    }

    private func testSupportSwiftFiles() throws -> [URL] {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let enumerator = FileManager.default.enumerator(
            at: testsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .filter {
                try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
    }

    private func supportSwiftFiles() throws -> [URL] {
        try testSupportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("Support.swift") }
    }

    private func sourceTermViolations(in fileURL: URL, terms: [String]) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

        return lines.enumerated().flatMap { lineOffset, line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.hasPrefix("import "),
                  !trimmedLine.hasPrefix("@testable import ")
            else {
                return [String]()
            }

            return terms.compactMap { term in
                guard line.contains(term) else {
                    return nil
                }

                return "\(fileURL.lastPathComponent):\(lineOffset + 1): \(term)"
            }
        }
    }

    private func countedTermMatches(in files: [URL], term: String) throws -> [String] {
        try files.compactMap { fileURL in
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let count = exactTermCount(in: contents, term: term)

            guard count > 0 else {
                return nil
            }

            return "\(fileURL.lastPathComponent):\(term):\(count)"
        }
        .sorted()
    }

    private func isNamedCoreBridgeBoundarySupport(_ fileName: String) -> Bool {
        fileName.hasSuffix("BridgeTestSupport.swift") || fileName.hasSuffix("CoreBridgeTestSupport.swift") ||
            fileName.hasSuffix("RealCoreTestSupport.swift")
    }

    private func isNamedBridgeBoundarySupport(_ fileName: String) -> Bool {
        fileName.hasSuffix("BridgeTestSupport.swift") || fileName.hasSuffix("CoreBridgeTestSupport.swift")
    }

    private func isNamedFileSystemBoundarySupport(_ fileName: String) -> Bool {
        fileName.hasSuffix("FileSystemTestSupport.swift") ||
            fileName.hasSuffix("RealCoreTestSupport.swift") || fileName.hasSuffix("RuntimeTestSupport.swift")
    }
}

extension TestSupportNamingGovernanceTests {
    func testInlineFeatureLocalDoublesStayInventoried() throws {
        let actual = try testSupportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("Tests.swift") }
            .flatMap(inlineTestDoubleDeclarations)
            .sorted()

        XCTAssertEqual(
            actual,
            inlineTestDoubleInventory,
            "Inline test doubles must be inventoried and should move to feature-local *TestDoubleSupport.swift."
        )
    }

    func testSelectedFeatureLocalRecordingDoublesExposeSemanticRequestAssertions() throws {
        let violations = try testSupportSwiftFiles()
            .filter { semanticRequestAssertionFileNames.contains($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: genericRequestAssertionTerms) }
            .sorted()
        XCTAssertEqual(violations, [], "Feature-local recording doubles should expose semantic request assertions.")
    }

    func testRecordingSupportExposesSemanticAssertionsInsteadOfRawRecordGetters() throws {
        let localRecordingFiles = try testSupportSwiftFiles()
            .filter { rawRecordLocalFileNames.contains($0.lastPathComponent) }
        let violations = try (supportSwiftFiles() + localRecordingFiles)
            .flatMap { try sourceTermViolations(in: $0, terms: rawRecordExposureTerms) }
            .sorted()
        XCTAssertEqual(violations, [], "Recording support should expose semantic assertions, not raw record getters.")
    }

    private func inlineTestDoubleDeclarations(in fileURL: URL) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        return contents.split(separator: "\n").compactMap { line in
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let kindIndex = tokens.firstIndex(where: { ["actor", "class", "struct"].contains($0) }),
                  tokens.indices.contains(kindIndex + 1)
            else {
                return nil
            }

            let typeName = tokens[kindIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: ":{"))
            guard inlineTestDoubleNameMarkers.contains(where: typeName.contains) else { return nil }
            return "\(fileURL.lastPathComponent):\(typeName)"
        }
    }
}
