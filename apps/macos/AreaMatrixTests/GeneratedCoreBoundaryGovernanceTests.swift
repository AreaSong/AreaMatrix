import XCTest

final class GeneratedCoreBoundaryGovernanceTests: MacOSGovernanceTestCase {
    private let functionCollisionInventory = [
        "Features/CommandPalette/CommandPaletteState.swift:runSmartList:1",
        "Features/Detail/MainDetailAITagSuggestionActions.swift:mapCoreError:2",
        "Features/Detail/MainDetailTagActions.swift:mapCoreError:2",
        "Features/Detail/MainDetailTagFilterRegistryActions.swift:mapCoreError:1",
        "Features/Detail/MainDetailTagSuggestionActions.swift:mapCoreError:4",
        "Features/FileActions/MainFileCategoryMoveActions.swift:mapCoreError:4",
        "Features/FileActions/MainFileDeleteActions.swift:mapCoreError:1",
        "Features/FileActions/MainFileRenameActions.swift:mapCoreError:1",
        "Features/Import/ImportBatchDuplicatePrecheck.swift:listFiles:1",
        "Features/Import/ImportSingleFilePreviewModel.swift:importFile:1",
        "Features/MainList/MainFileListBatchAITagActions.swift:mapCoreError:2",
        "Features/MainList/MainFileListDetailActions.swift:mapCoreError:2",
        "Features/MainList/MainFileListExternalSyncActions.swift:mapCoreError:5",
        "Features/MainList/MainFileListExternalSyncActions.swift:syncExternalChanges:1",
        "Features/MainList/MainFileListLoadingActions.swift:mapCoreError:2",
        "Features/MainList/MainFileListModel.swift:mapCoreError:1",
        "Features/Search/MainSearchModelSupport.swift:mapCoreError:3",
        "Features/Search/SemanticSearchActions.swift:mapCoreError:3",
        "Features/Search/SmartListActions.swift:mapCoreError:1",
        "Features/SyncConflicts/MainICloudConflictRoutingActions.swift:mapCoreError:3"
    ]

    private let nonPresentationStringRouteInventory = [
        "Features/AI/AIClassificationSuggestionApplyState.swift:368: var route: String",
        "Features/CommandPalette/CommandPaletteState.swift:120: var route: String"
    ]

    func testGeneratedCoreCallsStayInsideBridge() throws {
        let violations = try productionSwiftFiles()
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bAreaMatrix\.[A-Za-z_][A-Za-z0-9_]*\s*\("#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Swift production code must call Rust Core through Bridge/CoreBridge, not generated UniFFI bindings."
        )
    }

    func testBareGeneratedCoreFunctionNamesStayInsideBridgeOrInExactCollisionInventory() throws {
        let bindingURL = productionDirectory()
            .appendingPathComponent("Bridge/UniFFI/area_matrix.swift")
        let bindingSource = try String(contentsOf: bindingURL, encoding: .utf8)
        let declarationRegex = try NSRegularExpression(
            pattern: #"(?m)^public func ([a-z][A-Za-z0-9_]*)\("#
        )
        let sourceRange = NSRange(bindingSource.startIndex ..< bindingSource.endIndex, in: bindingSource)
        let functionNames: [String] = declarationRegex.matches(in: bindingSource, range: sourceRange)
            .compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: bindingSource) else { return nil }
                return String(bindingSource[range])
            }
        XCTAssertFalse(functionNames.isEmpty, "Tracked UniFFI bindings must expose generated Core functions.")

        let alternation = functionNames
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        let actual = try countedRegexMatches(
            in: productionSwiftFiles().filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") },
            pattern: #"(?<!func )(?<![.A-Za-z0-9_])(?:"# + alternation + #")(?=\s*\()"#
        )

        XCTAssertEqual(
            actual,
            functionCollisionInventory,
            "Bare names that collide with generated Core functions must stay exactly inventoried; " +
                "new Core calls belong behind Bridge/CoreBridge."
        )
    }

    func testPresentationRoutesDoNotUseStringState() throws {
        let routePattern = #"\b(?:var|let)\s+(?:route|destination|[A-Za-z0-9_]+Route|"#
            + #"[A-Za-z0-9_]+Destination)\s*:\s*String\b"#
        let violations = try productionSwiftFiles()
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") }
            .flatMap { try sourceRegexViolations(in: $0, pattern: routePattern) }
            .sorted()

        XCTAssertEqual(
            violations,
            nonPresentationStringRouteInventory,
            "String route fields are limited to exact Core metadata projections; mutually exclusive " +
                "presentation destinations must use feature-owned typed routes."
        )
    }

    func testGeneratedCoreTypeUseOutsideBridgeCannotGrow() throws {
        let generatedTypes = try generatedPublicCoreTypeNames()
        let actual = try generatedCoreTypeUsageInventory(generatedTypes: generatedTypes)
        let expected = try generatedCoreTypeUsageBaseline()

        XCTAssertEqual(
            actual,
            expected,
            "Generated UniFFI types outside Bridge are an exact legacy inventory. " +
                "New feature code must consume Bridge-owned snapshots; " +
                "migrate existing rows instead of growing this baseline."
        )
    }

    private func generatedPublicCoreTypeNames() throws -> [String] {
        let bindingURL = productionDirectory()
            .appendingPathComponent("Bridge/UniFFI/area_matrix.swift")
        let source = try String(contentsOf: bindingURL, encoding: .utf8)
        let regex = try NSRegularExpression(
            pattern: #"(?m)^public (?:struct|enum|class|protocol|typealias) ([A-Z][A-Za-z0-9_]*)"#
        )
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        let names = regex.matches(in: source, range: range).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        }
        let governed = Set(names.filter {
            !$0.hasPrefix("FfiConverter") && !$0.hasPrefix("Uniffi")
        })
        XCTAssertFalse(governed.isEmpty, "Tracked UniFFI bindings must expose public generated types.")
        return governed.sorted { $0.count > $1.count }
    }

    private func generatedCoreTypeUsageInventory(generatedTypes: [String]) throws -> [String] {
        let alternation = generatedTypes
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let regex = try NSRegularExpression(pattern: #"\b("# + alternation + #")\b"#)
        return try productionSwiftFiles()
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") }
            .compactMap { fileURL -> String? in
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let range = NSRange(source.startIndex ..< source.endIndex, in: source)
                var counts: [String: Int] = [:]
                for match in regex.matches(in: source, range: range) {
                    guard let range = Range(match.range(at: 1), in: source) else { continue }
                    counts[String(source[range]), default: 0] += 1
                }
                guard !counts.isEmpty else { return nil }
                let entries = counts.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",")
                return "\(relativeProductionPath(for: fileURL))|\(entries)"
            }
            .sorted()
    }

    private func generatedCoreTypeUsageBaseline() throws -> [String] {
        let baselineURL = testsDirectory()
            .appendingPathComponent("GovernanceBaselines/GeneratedCoreTypeUsage.txt")
        let source = try String(contentsOf: baselineURL, encoding: .utf8)
        return source.split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .sorted()
    }
}
