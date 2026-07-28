import AppKit
@testable import AreaMatrix
import XCTest

@MainActor
final class ObservabilityApplicationLifecycleTests: XCTestCase {
    func testRepeatedTerminationRequestsRunOneStopAndOneReply() async {
        let lifecycle = ObservabilityApplicationLifecycle()
        let probe = TerminationProbe()
        let replyExpectation = expectation(description: "termination reply")

        let first = lifecycle.beginTermination(
            stop: { await probe.stop() },
            reply: {
                probe.reply()
                replyExpectation.fulfill()
            }
        )
        await probe.waitUntilStopEntered()
        let second = lifecycle.beginTermination(
            stop: { await probe.stop() },
            reply: { probe.reply() }
        )

        XCTAssertEqual(first, .terminateLater)
        XCTAssertEqual(second, .terminateLater)
        XCTAssertEqual(probe.stopCount, 1)
        probe.allowStopToFinish()
        await fulfillment(of: [replyExpectation], timeout: 1)
        XCTAssertEqual(probe.replyCount, 1)

        _ = lifecycle.beginTermination(stop: { await probe.stop() }, reply: { probe.reply() })
        await Task.yield()
        XCTAssertEqual(probe.stopCount, 1)
        XCTAssertEqual(probe.replyCount, 1)
    }

    func testTerminationRepliesAfterDegradedStopReport() async {
        let lifecycle = ObservabilityApplicationLifecycle()
        let replyExpectation = expectation(description: "degraded stop still replies")
        let result = lifecycle.beginTermination(
            stop: {
                ObservabilityStopReport(
                    failures: [.init(stage: .coreFlush, code: "operation-failed")]
                )
            },
            reply: { replyExpectation.fulfill() }
        )

        XCTAssertEqual(result, .terminateLater)
        await fulfillment(of: [replyExpectation], timeout: 1)
    }

    func testTerminationRetainsLifecycleUntilReplyThenReleasesIt() async {
        var lifecycle: ObservabilityApplicationLifecycle? = ObservabilityApplicationLifecycle()
        weak var weakLifecycle = lifecycle
        let probe = TerminationProbe()
        let replyExpectation = expectation(description: "retained lifecycle replies")

        _ = lifecycle?.beginTermination(
            stop: { await probe.stop() },
            reply: { replyExpectation.fulfill() }
        )
        await probe.waitUntilStopEntered()
        lifecycle = nil
        XCTAssertNotNil(weakLifecycle)

        probe.allowStopToFinish()
        await fulfillment(of: [replyExpectation], timeout: 1)
        await Task.yield()
        XCTAssertNil(weakLifecycle)
    }
}

@MainActor
private final class TerminationProbe {
    private let stopEntered = ObservabilityTestLatch()
    private let releaseStop = ObservabilityTestLatch()
    private(set) var stopCount = 0
    private(set) var replyCount = 0

    func stop() async -> ObservabilityStopReport {
        stopCount += 1
        await stopEntered.open()
        await releaseStop.wait()
        var report = ObservabilityStopReport()
        report.cleanSessionMarkerWritten = true
        return report
    }

    func waitUntilStopEntered() async {
        await stopEntered.wait()
    }

    func allowStopToFinish() {
        Task { await releaseStop.open() }
    }

    func reply() {
        replyCount += 1
    }
}

private actor ObservabilityTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}
