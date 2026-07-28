@testable import AreaMatrix
import Foundation
import XCTest

final class ObservabilityConfigurationTests: XCTestCase {
    func testTimedLeaseExpiresAtBoundaryAndResetsWholeConfiguration() {
        let configured = developerConfiguration().activating(
            policy: .timed,
            durationHours: 1,
            nowMilliseconds: 1000,
            sessionID: "session-a"
        )

        XCTAssertEqual(resolve(configured, now: 3_600_999, session: "session-b"), configured)
        XCTAssertEqual(resolve(configured, now: 3_601_000, session: "session-b"), .standard)
    }

    func testNextLaunchLeaseOnlyRemainsInActivationSession() {
        let configured = developerConfiguration().activating(
            policy: .nextLaunch,
            durationHours: 1,
            nowMilliseconds: 1000,
            sessionID: "session-a"
        )

        XCTAssertEqual(resolve(configured, now: 2000, session: "session-a"), configured)
        XCTAssertEqual(resolve(configured, now: 2000, session: "session-b"), .standard)
    }

    func testManualAndLegacyDeveloperConfigurationsRemainEnabled() {
        let manual = developerConfiguration().activating(
            policy: .manual,
            durationHours: 1,
            nowMilliseconds: 1000,
            sessionID: "session-a"
        )

        XCTAssertEqual(resolve(manual, now: 9000, session: "session-b"), manual)
        XCTAssertEqual(resolve(developerConfiguration(), now: 9000, session: "session-b"), developerConfiguration())
    }

    func testStandardAndDisabledModesDiscardStaleLease() {
        let lease = AppObservabilityModeLease(
            policy: .manual,
            activatedAtMilliseconds: 1,
            activationSessionID: "session-a",
            expiresAtMilliseconds: nil
        )
        var standard = AppObservabilityConfiguration.standard
        standard.modeLease = lease
        var disabled = standard
        disabled.mode = .disabled

        XCTAssertNil(resolve(standard, now: 2, session: "session-b").modeLease)
        XCTAssertNil(resolve(disabled, now: 2, session: "session-b").modeLease)
    }

    private func resolve(
        _ configuration: AppObservabilityConfiguration,
        now: Int64,
        session: String
    ) -> AppObservabilityConfiguration {
        ObservabilityConfigurationResolver.resolveForLaunch(
            configuration,
            nowMilliseconds: now,
            sessionID: session
        )
    }

    private func developerConfiguration() -> AppObservabilityConfiguration {
        AppObservabilityConfiguration(
            mode: .developer,
            minimumSeverity: .trace,
            diskBudgetBytes: 2 * 1024 * 1024 * 1024,
            retentionHours: 720,
            includeSensitive: true
        )
    }
}
