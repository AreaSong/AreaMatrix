@testable import AreaMatrix

@MainActor
final class RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    var messages: [String] {
        announcements
    }

    func announce(_ message: String) {
        announcements.append(message)
    }
}

struct NoopAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: String) {}
}
