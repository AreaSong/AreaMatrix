import AppKit
import Foundation

@MainActor
final class ObservabilityApplicationLifecycle {
    private var terminationTask: Task<Void, Never>?
    private var didReply = false

    func beginTermination(
        stop: @escaping @MainActor () async -> ObservabilityStopReport,
        reply: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { [self] in
            _ = await stop()
            guard !didReply else { return }
            didReply = true
            reply()
        }
        return .terminateLater
    }
}
