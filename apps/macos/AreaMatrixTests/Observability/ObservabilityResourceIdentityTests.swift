@testable import AreaMatrix
import Foundation
import XCTest

final class ObservabilityResourceIdentityTests: XCTestCase {
    func testIdentityIsStableForOneInstallationKeyAndContainsNoFileName() {
        let identifiers = TestObservabilityIdentifierSequence([
            "00000000-0000-4000-8000-000000000001",
            "00000000-0000-4000-8000-000000000002"
        ])
        let factory = ObservabilityResourceIdentityFactory(
            keyData: Data(repeating: 0x11, count: 32),
            idGenerator: { identifiers.next() }
        )
        let source = URL(fileURLWithPath: "/tmp/private-client/Quarterly Report.PDF")

        let first = factory.reference(for: source, storageMode: "copied", fileSize: 5 * 1024 * 1024)
        let second = factory.reference(for: source, storageMode: "copied", fileSize: 5 * 1024 * 1024)

        XCTAssertEqual(first.alias, second.alias)
        XCTAssertNotEqual(first.resourceId, second.resourceId)
        XCTAssertNotNil(UUID(uuidString: first.resourceId))
        XCTAssertFalse(first.alias.localizedCaseInsensitiveContains("quarterly"))
        XCTAssertEqual(first.extension, "pdf")
        XCTAssertEqual(first.sizeBucket, "1mb_10mb")
        XCTAssertEqual(first.storageMode, "copied")
    }

    func testDifferentInstallationKeysProduceDifferentPseudonyms() {
        let source = URL(fileURLWithPath: "/tmp/private-client/Quarterly Report.pdf")
        let first = ObservabilityResourceIdentityFactory(keyData: Data(repeating: 0x11, count: 32))
            .reference(for: source, storageMode: "indexed", fileSize: 512)
        let second = ObservabilityResourceIdentityFactory(keyData: Data(repeating: 0x22, count: 32))
            .reference(for: source, storageMode: "indexed", fileSize: 512)

        XCTAssertNotEqual(first.alias, second.alias)
        XCTAssertNotEqual(first.resourceId, second.resourceId)
        XCTAssertEqual(first.sizeBucket, "lt_1mb")
    }

    func testUnsafeExtensionIsOmittedBeforeCoreValidation() {
        let factory = ObservabilityResourceIdentityFactory(keyData: Data(repeating: 0x33, count: 32))
        let reference = factory.reference(
            for: URL(fileURLWithPath: "/tmp/example.文档"),
            storageMode: "moved",
            fileSize: 2 * 1024 * 1024 * 1024
        )

        XCTAssertNil(reference.extension)
        XCTAssertEqual(reference.sizeBucket, "gte_1gb")
    }

    func testKeyStoreFailureOmitsResourceReferenceAndReportsDegradation() async {
        let provider = ObservabilityResourceIdentityProvider(keyStore: FailingObservabilityAliasKeyStore())

        let result = await provider.identity(
            for: URL(fileURLWithPath: "/tmp/private-client/report.pdf"),
            storageMode: .copied
        )

        XCTAssertNil(result.reference)
        XCTAssertEqual(result.degradedReason, "resource-alias-key-unavailable")
    }
}

private struct FailingObservabilityAliasKeyStore: ObservabilityAliasKeyStoring {
    func load() throws -> Data? {
        throw TestError.unavailable
    }

    func save(_: Data) throws {
        throw TestError.unavailable
    }

    private enum TestError: Error {
        case unavailable
    }
}
