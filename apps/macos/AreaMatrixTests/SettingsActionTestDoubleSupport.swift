@testable import AreaMatrix
import XCTest

struct StaticAppVersionReader: AppVersionReading {
    let version: String

    func appVersion() -> String {
        version
    }
}

struct NoopAboutExternalLinkOpener: AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        link.urlString
    }
}

@MainActor
final class RecordingAboutExternalLinkOpener: AboutExternalLinkOpening {
    private let result: (AboutExternalLink) throws -> String
    private var openedLinks: [AboutExternalLink] = []

    init(result: @escaping (AboutExternalLink) throws -> String = { $0.urlString }) {
        self.result = result
    }

    func open(link: AboutExternalLink) throws -> String {
        openedLinks.append(link)
        return try result(link)
    }
}

@MainActor
final class RecordingAboutStringCopier: AboutStringCopying {
    private let result: Result<Void, Error>
    private var values: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func copy(_ value: String) throws {
        values.append(value)
        try result.get()
    }

    func assertCopiedValues(
        _ expectedValues: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(values, expectedValues, file: file, line: line)
    }
}

@MainActor
final class RecordingAdvancedDiagnosticCopier: AdvancedSettingsDiagnosticSummaryCopying {
    private let result: Result<Void, Error>
    private var copiedSummaries: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func copyDiagnosticSummary(_ summary: String) throws {
        copiedSummaries.append(summary)
        try result.get()
    }

    func assertCopiedSummary(
        contains expectedFragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(copiedSummaries.count, 1, file: file, line: line)
        guard let copiedSummary = copiedSummaries.first else {
            return
        }

        for fragment in expectedFragments {
            XCTAssertTrue(copiedSummary.contains(fragment), file: file, line: line)
        }
    }
}
