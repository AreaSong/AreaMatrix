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
final class RecordingAboutLogsOpener: AboutLogsOpening {
    private let result: (String, String) throws -> String
    private var openedRepoPaths: [String] = []

    init(result: @escaping (String, String) throws -> String = { _, path in path }) {
        self.result = result
    }

    func logsPath(repoPath: String) -> String {
        "\(repoPath)/.areamatrix/logs"
    }

    func openLogs(repoPath: String) throws -> String {
        openedRepoPaths.append(repoPath)
        let path = logsPath(repoPath: repoPath)
        return try result(repoPath, path)
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

struct NoopAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    @MainActor
    func revealDiagnostics(at _: String) throws {}
}

@MainActor
final class RecordingAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    private let result: Result<Void, Error>
    private var paths: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func revealDiagnostics(at path: String) throws {
        paths.append(path)
        try result.get()
    }
}

@MainActor
final class RecordingAdvancedSettingsLogsOpener: AdvancedSettingsLogFolderOpening {
    private let result: Result<String, Error>
    private var openedRepoPaths: [String] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    convenience init(logsPath: String) {
        self.init(result: .success(logsPath))
    }

    func openLogsFolder(repoPath: String) throws -> String {
        openedRepoPaths.append(repoPath)
        return try result.get()
    }

    func assertOpenedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openedRepoPaths, expectedRepoPaths, file: file, line: line)
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
