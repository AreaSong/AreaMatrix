import Foundation
import XCTest

extension MacOSArchitectureBoundaryGovernanceTests {
    func testCoreBridgeContractPackageOwnsFileReadingContracts() throws {
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreFileReadingContracts.swift"])
        for declaration in [
            "public protocol CoreFileListing",
            "public protocol CoreFileDetailing",
            "public struct FileFilterSnapshot",
            "public struct FileEntrySnapshot",
            "public enum FileAvailabilitySnapshot",
            "public enum CoreImportCommitState"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared file-reading contract: \(declaration)")
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))

        let appSource = try String(
            contentsOf: productionDirectory().appendingPathComponent("Bridge/CoreFileListing.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(appSource.contains("protocol CoreFileListing"))
        XCTAssertFalse(appSource.contains("protocol CoreFileDetailing"))
        XCTAssertFalse(appSource.contains("struct FileFilterSnapshot"))
        XCTAssertFalse(appSource.contains("struct FileEntrySnapshot"))
    }
}
