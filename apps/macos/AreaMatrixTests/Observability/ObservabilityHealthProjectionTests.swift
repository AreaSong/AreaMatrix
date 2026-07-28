@testable import AreaMatrix
import XCTest

final class ObservabilityHealthProjectionTests: XCTestCase {
    func testHealthReportsModeElapsedAndEstimatedGrowthWithoutMutatingStore() async throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 1000)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "growth-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date }
        )
        await hub.configure(contractConfiguration(mode: .developer))
        let baseline = await hub.health(core: nil)

        await hub.ingestCoreEvent(contractEvent(
            id: "growth-event",
            timestamp: 1001,
            sessionID: "growth-session"
        ))
        clock.milliseconds = 3_601_000
        let measured = await hub.health(core: nil)

        XCTAssertEqual(measured.modeElapsedMilliseconds, 3_600_000)
        XCTAssertEqual(
            measured.estimatedGrowthBytesPerHour,
            measured.fileUsageBytes - baseline.fileUsageBytes
        )

        await hub.configure(contractConfiguration(mode: .disabled))
        let disabled = await hub.health(core: nil)
        XCTAssertEqual(disabled.modeElapsedMilliseconds, 0)
        XCTAssertNil(disabled.estimatedGrowthBytesPerHour)
    }

    func testEstimatedGrowthArithmeticIsBoundedAndRequiresAWindow() {
        XCTAssertNil(ObservabilityHubPolicy.estimatedGrowthBytesPerHour(
            currentBytes: 200,
            baselineBytes: 100,
            elapsedMilliseconds: 0,
            persistsToDisk: true
        ))
        XCTAssertNil(ObservabilityHubPolicy.estimatedGrowthBytesPerHour(
            currentBytes: 200,
            baselineBytes: 100,
            elapsedMilliseconds: 1,
            persistsToDisk: false
        ))
        XCTAssertEqual(ObservabilityHubPolicy.estimatedGrowthBytesPerHour(
            currentBytes: 300,
            baselineBytes: 100,
            elapsedMilliseconds: 7_200_000,
            persistsToDisk: true
        ), 100)
        XCTAssertEqual(ObservabilityHubPolicy.estimatedGrowthBytesPerHour(
            currentBytes: .max,
            baselineBytes: 0,
            elapsedMilliseconds: 1,
            persistsToDisk: true
        ), .max)
    }
}
