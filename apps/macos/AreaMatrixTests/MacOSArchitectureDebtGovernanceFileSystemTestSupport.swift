import Foundation
import XCTest

struct TypeSpanBudget {
    let type: String
    let owner: String
    let maximumFiles: Int
    let maximumExtensions: Int
}

struct TypeSpan {
    let fileCount: Int
    let extensionCount: Int
}

func featureName(for file: URL, root: URL) -> String {
    file.path.dropFirst(root.path.count + 1).split(separator: "/").first.map(String.init) ?? ""
}

/// Maps the historical feature directories to the five physical SwiftPM groups.
/// Directory-to-directory references inside one group are intentional implementation
/// details; only group-to-group references are architecture edges.
func featureModuleName(_ feature: String) -> String {
    switch feature {
    case "AI": "AI"
    case "CommandPalette", "Detail", "MainList", "Search": "Library"
    case "FileActions", "SyncConflicts": "Operation"
    case "Import", "Onboarding", "RepositoryLifecycle": "Ingestion"
    case "Settings": "Settings"
    case "Diagnostics": "Diagnostics"
    default: feature
    }
}

func capturedRegexMatches(in source: String, pattern: String) throws -> [String] {
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex ..< source.endIndex, in: source)
    return expression.matches(in: source, range: range).compactMap { match in
        guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }
}

func assertMigratedFeatureDependencies(
    productionDirectory: URL,
    macOSDirectory: URL
) throws {
    for relativePath in [
        "Features/Onboarding/OnboardingSystemCapabilities.swift",
        "Features/Import/ImportFolderScanState.swift",
        "Features/MainList/MainListSelectionState.swift",
        "Features/AI/RemoteProviderConfigDraft.swift"
    ] {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: productionDirectory.appendingPathComponent(relativePath).path
            ),
            "Migrated App-owned shim must not return: \(relativePath)"
        )
    }

    let projectSource = try String(
        contentsOf: macOSDirectory.appendingPathComponent("AreaMatrix.xcodeproj/project.pbxproj"),
        encoding: .utf8
    )
    let testTargetStart = try XCTUnwrap(
        projectSource.range(of: "productName = AreaMatrixTests;"),
        "Missing AreaMatrixTests target"
    )
    let testTargetPrefix = projectSource[..<testTargetStart.lowerBound]
    let frameworksStart = try XCTUnwrap(
        testTargetPrefix.range(of: "files = (", options: .backwards),
        "Missing AreaMatrixTests Frameworks phase"
    )
    let frameworksBlock = String(testTargetPrefix[frameworksStart.lowerBound...])
    for product in [
        "AreaMatrixFeatureLibrary",
        "AreaMatrixFeatureIngestion",
        "AreaMatrixFeatureOperation",
        "AreaMatrixFeatureSettings",
        "AreaMatrixFeatureAI"
    ] {
        XCTAssertTrue(frameworksBlock.contains("\(product) in Frameworks"))
    }
}

func packageForwardingTypealiases(
    in files: [URL],
    productionDirectory: URL
) throws -> [String] {
    let featureRoot = productionDirectory.appendingPathComponent("Features", isDirectory: true)
    let expression = try NSRegularExpression(
        pattern: #"(?m)^typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*AreaMatrixFeature"#
    )
    return try files
        .filter { $0.path.hasPrefix(featureRoot.path + "/") }
        .flatMap { file -> [String] in
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex ..< source.endIndex, in: source)
            return expression.matches(in: source, range: range).compactMap { match in
                guard let nameRange = Range(match.range(at: 1), in: source) else { return nil }
                let relativePath = file.path.dropFirst(productionDirectory.path.count + 1)
                return "\(relativePath):\(source[nameRange])"
            }
        }
}

extension MacOSArchitectureDebtGovernanceTests {
    func typeSpans(in files: [URL]) throws -> [String: TypeSpan] {
        var pathsByType: [String: Set<String>] = [:]
        var extensionCounts: [String: Int] = [:]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let declarationPattern = #"(?m)^(?:public\s+|internal\s+|private\s+|fileprivate\s+)?(?:final\s+)?"# +
                #"(?:class|struct|enum|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#
            for name in try capturedRegexMatches(in: source, pattern: declarationPattern) {
                pathsByType[name, default: []].insert(relativeProductionPath(for: file))
            }
            for name in try capturedRegexMatches(in: source, pattern: #"(?m)^extension\s+([A-Za-z_][A-Za-z0-9_]*)"#) {
                pathsByType[name, default: []].insert(relativeProductionPath(for: file))
                extensionCounts[name, default: 0] += 1
            }
        }
        return pathsByType.reduce(into: [String: TypeSpan]()) { result, entry in
            result[entry.key] = TypeSpan(
                fileCount: entry.value.count,
                extensionCount: extensionCounts[entry.key, default: 0]
            )
        }
    }

    func crossFeatureExtensions() throws -> Set<String> {
        let featureRoot = productionDirectory().appendingPathComponent("Features", isDirectory: true)
        let files = try productionSwiftFiles().filter { $0.path.hasPrefix(featureRoot.path + "/") }
        let owners = try uniqueFeatureTypeOwners(in: files, featureRoot: featureRoot)
        var violations: Set<String> = []
        for file in files {
            let feature = featureName(for: file, root: featureRoot)
            let source = try String(contentsOf: file, encoding: .utf8)
            for type in try capturedRegexMatches(in: source, pattern: #"(?m)^extension\s+([A-Za-z_][A-Za-z0-9_]*)"#) {
                guard let owner = owners[type], featureModuleName(owner) != featureModuleName(feature) else { continue }
                let relativePath = relativeProductionPath(for: file)
                violations.insert("\(featureModuleName(feature))|\(featureModuleName(owner))|\(type)|\(relativePath)")
            }
        }
        return violations
    }

    func directCrossFeatureDependencies() throws -> Set<String> {
        let featureRoot = productionDirectory().appendingPathComponent("Features", isDirectory: true)
        let files = try productionSwiftFiles().filter { $0.path.hasPrefix(featureRoot.path + "/") }
        let owners = try uniqueFeatureTypeOwners(in: files, featureRoot: featureRoot)
        var edges: Set<String> = []
        for file in files {
            let consumer = featureModuleName(featureName(for: file, root: featureRoot))
            let source = try String(contentsOf: file, encoding: .utf8)
            let identifiers = try Set(capturedRegexMatches(in: source, pattern: #"\b([A-Za-z_][A-Za-z0-9_]*)\b"#))
            for type in identifiers {
                guard let owner = owners[type], featureModuleName(owner) != consumer else { continue }
                edges.insert("\(consumer)->\(featureModuleName(owner))")
            }
        }
        return edges
    }

    private func uniqueFeatureTypeOwners(in files: [URL], featureRoot: URL) throws -> [String: String] {
        var declaringFeatures: [String: Set<String>] = [:]
        let declarationPattern = #"(?m)^(?:public\s+|internal\s+|private\s+|fileprivate\s+)?(?:final\s+)?"# +
            #"(?:class|struct|enum|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        for file in files {
            let feature = featureName(for: file, root: featureRoot)
            let source = try String(contentsOf: file, encoding: .utf8)
            for type in try capturedRegexMatches(in: source, pattern: declarationPattern) {
                declaringFeatures[type, default: []].insert(feature)
            }
        }
        return declaringFeatures.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}
