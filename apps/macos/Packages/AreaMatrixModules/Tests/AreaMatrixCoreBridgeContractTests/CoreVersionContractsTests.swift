import AreaMatrixCoreBridgeContract
import XCTest

final class CoreVersionContractsTests: XCTestCase {
    func testVersionCapabilityProtocolsCanShareAValueOnlyImplementation() async throws {
        let source = VersionSource(version: "1.2.3")
        let reader: any CoreVersionReading = source
        let loader: any CoreVersionLoading = source

        let readerVersion = try await reader.coreVersion()
        let loaderVersion = try await loader.coreVersion()

        XCTAssertEqual(readerVersion, "1.2.3")
        XCTAssertEqual(loaderVersion, "1.2.3")
    }
}

private struct VersionSource: CoreVersionReading, CoreVersionLoading {
    let version: String

    func coreVersion() async throws -> String {
        version
    }
}
