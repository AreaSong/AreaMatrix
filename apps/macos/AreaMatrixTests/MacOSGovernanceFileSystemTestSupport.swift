import XCTest

class MacOSGovernanceTestCase: XCTestCase {}

extension MacOSGovernanceTestCase {
    var appPlatformServiceFiles: Set<String> {
        [
            "App/AppPlatformServices.swift",
            "App/AppPlatformServiceAdapters.swift",
            "App/LocalFileURLPlatformAdapters.swift"
        ]
    }

    func productionSwiftFiles() throws -> [URL] {
        try swiftFiles(in: productionDirectory())
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/Generated/") }
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/UniFFI/") }
    }

    func handwrittenMacOSSwiftFiles() throws -> [URL] {
        try [productionDirectory(), testsDirectory()]
            .flatMap(swiftFiles)
            .filter { !relativeMacOSPath(for: $0).hasPrefix("AreaMatrix/Bridge/Generated/") }
            .filter { !relativeMacOSPath(for: $0).hasPrefix("AreaMatrix/Bridge/UniFFI/") }
    }

    func productionDirectory() -> URL {
        testsDirectory().deletingLastPathComponent()
            .appendingPathComponent("AreaMatrix", isDirectory: true)
    }

    func productionFeatureDirectories() throws -> [String] {
        let featuresDirectory = productionDirectory().appendingPathComponent("Features", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: featuresDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try entries
            .filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    func testsDirectory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    func generatedBindingArtifacts() throws -> [String] {
        try ["Bridge/Generated", "Bridge/UniFFI"].flatMap { relativeDirectory in
            let directoryURL = productionDirectory().appendingPathComponent(relativeDirectory, isDirectory: true)
            let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return try (enumerator?.compactMap { $0 as? URL } ?? [])
                .filter { try isRegularFile($0) }
                .map { relativeProductionPath(for: $0) }
        }
        .sorted()
    }

    func isRegularFile(_ fileURL: URL) throws -> Bool {
        try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    }

    func isViewLikeProductionFile(_ fileURL: URL) -> Bool {
        let relativePath = relativeProductionPath(for: fileURL)
        if relativePath.hasPrefix("Views/") { return true }

        let fileName = fileURL.lastPathComponent
        let viewSuffixes = ["View.swift", "Pane.swift", "Sheet.swift", "Section.swift", "Row.swift", "Panel.swift"]
        return relativePath.hasPrefix("Features/") && viewSuffixes.contains { fileName.hasSuffix($0) }
    }

    func relativeProductionPath(for fileURL: URL) -> String {
        let marker = "/AreaMatrix/"
        guard let range = fileURL.path.range(of: marker, options: .backwards) else {
            return fileURL.lastPathComponent
        }
        return String(fileURL.path[range.upperBound...])
    }

    func relativeMacOSPath(for fileURL: URL) -> String {
        let macOSDirectory = testsDirectory().deletingLastPathComponent().path + "/"
        guard fileURL.path.hasPrefix(macOSDirectory) else {
            return fileURL.lastPathComponent
        }
        return String(fileURL.path.dropFirst(macOSDirectory.count))
    }

    func swiftLineCount(in fileURL: URL) throws -> Int {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let newlineCount = contents.reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        }
        return newlineCount + (contents.hasSuffix("\n") ? 0 : 1)
    }

    func sourceTermViolations(in fileURL: URL, terms: [String]) throws -> [String] {
        try sourceLineViolations(in: fileURL) { line in
            terms.filter { line.contains($0) }
        }
    }

    func sourceRegexViolations(in fileURL: URL, pattern: String) throws -> [String] {
        try sourceLineViolations(in: fileURL) { line in
            try regexMatches(in: line, pattern: pattern)
        }
    }

    func countedRegexMatches(in fileURLs: [URL], pattern: String) throws -> [String] {
        let matches = try fileURLs.flatMap { fileURL in
            try sourceRegexMatches(in: fileURL, pattern: pattern)
        }
        let counts = Dictionary(grouping: matches, by: { $0 }).mapValues(\.count)
        return counts.map { "\($0.key):\($0.value)" }.sorted()
    }

    func sourceRegexMatches(in fileURL: URL, pattern: String) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line in
            try regexMatches(in: String(line), pattern: pattern).map {
                "\(relativeProductionPath(for: fileURL)):\($0)"
            }
        }
    }

    func regexMatches(in line: String, pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            return String(line[range])
        }
    }

    func sourceLineViolations(in fileURL: URL, matches: (String) throws -> [String]) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { offset, line in
                try matches(String(line)).map {
                    "\(relativeProductionPath(for: fileURL)):\(offset + 1): \($0)"
                }
            }
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .filter { try isRegularFile($0) }
    }
}
