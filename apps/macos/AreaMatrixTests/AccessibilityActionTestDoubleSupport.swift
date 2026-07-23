@testable import AreaMatrix
import XCTest

@MainActor
final class RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private var announcements: [LocalizedMessage] = []

    func announce(_ message: LocalizedMessage) {
        announcements.append(message)
    }

    func assertAnnouncements(
        _ expectedAnnouncements: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(announcements.map(L10n.resolve), expectedAnnouncements, file: file, line: line)
    }

    func assertAnnouncementDescriptors(
        _ expectedAnnouncements: [LocalizedMessage],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(announcements, expectedAnnouncements, file: file, line: line)
    }
}

struct NoopAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: LocalizedMessage) {}
}
