@testable import AreaMatrix
import XCTest

@MainActor
final class RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }

    func assertAnnouncements(
        _ expectedAnnouncements: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(announcements, expectedAnnouncements, file: file, line: line)
    }
}

struct NoopAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: String) {}
}
