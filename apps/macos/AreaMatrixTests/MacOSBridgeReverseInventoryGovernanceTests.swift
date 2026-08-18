import Foundation
import XCTest

final class BridgeReverseInventoryGovernanceTests: MacOSGovernanceTestCase {
    private let featureOwnedConformanceInventory = [
        FeatureOwnedBridgeConformance(
            protocolName: "ICloudConflictResolving",
            declarationPath: "Features/SyncConflicts/ICloudConflictMinimalResolution.swift",
            owner: "SyncConflicts"
        )
    ]

    private let inventory = [
        BridgeContractOwner("CoreBatchChangeCategory.swift", ["CoreBatchCategoryChanging"], "FileActions"),
        BridgeContractOwner("CoreBatchDelete.swift", ["CoreBatchDeleting"], "FileActions"),
        BridgeContractOwner("CoreClassifierRuleEditing.swift", ["CoreClassifierRuleEditing"], "Settings"),
        BridgeContractOwner(
            "CoreClassifierRuleSavingAndImpactPreviewing.swift",
            ["CoreClassifierImpactPreviewing", "CoreClassifierRuleSaving"],
            "Settings / FileActions"
        ),
        BridgeContractOwner(
            "CoreErrorMappingSnapshots.swift",
            ["AppErrorMappingProviding", "CoreErrorMapping"],
            "Shared error presentation"
        ),
        BridgeContractOwner("CoreExternalChangesSyncing.swift", ["CoreExternalChangesSyncing"], "MainList"),
        BridgeContractOwner(
            "CoreFileDeleting.swift",
            [
                "CoreAISettingsLoading", "CoreAISettingsUpdating", "CoreFileDeleting",
                "CoreSemanticFallbackStatusReading", "CoreSemanticSearching"
            ],
            "FileActions / AI / Search"
        ),
        BridgeContractOwner(
            "CoreFileListing.swift",
            ["CoreMissingFileRecovering", "FileAvailabilityChecking"],
            "Library"
        ),
        BridgeContractOwner("CoreFileRenaming.swift", ["CoreBatchRenaming", "CoreFileRenaming"], "FileActions"),
        BridgeContractOwner(
            "CoreICloudConflictListing.swift",
            ["CoreICloudConflictListing", "CoreICloudConflictReviewing"],
            "SyncConflicts"
        ),
        BridgeContractOwner("CoreImportConflictBatching.swift", ["CoreImportConflictBatching"], "Import"),
        BridgeContractOwner("CoreImportObservability.swift", ["CoreObservedFileImporting"], "Import observability"),
        BridgeContractOwner(
            "CoreImporting.swift",
            ["CoreBatchCopyImporting", "CoreFileImporting"],
            "Import"
        ),
        BridgeContractOwner(
            "CoreMetadataRepairing.swift",
            ["CoreMetadataRepairing", "CoreRepositoryReindexing"],
            "RepositoryLifecycle"
        ),
        BridgeContractOwner("CoreMoveToCategory.swift", ["CoreFileCategoryMoving"], "FileActions"),
        BridgeContractOwner(
            "CoreNoteReadingWriting.swift",
            [
                "CoreAIPrivacyEvaluating",
                "CoreAISummaryManaging",
                "CoreNoteReadingWriting",
                "RepositoryContentLocaleSnapshotting"
            ],
            "Detail / AI"
        ),
        BridgeContractOwner(
            "CoreObservabilityBridge.swift",
            ["CoreObservabilityControlling", "CoreObservabilityEventSinking"],
            "Observability"
        ),
        BridgeContractOwner("CoreOverviewRegenerating.swift", ["CoreOverviewRegenerating"], "RepositoryLifecycle"),
        BridgeContractOwner(
            "CoreRemoteProviderConfiguring.swift",
            [
                "CoreAIClassificationFallbackStatusReading", "CoreAIClassificationSuggesting",
                "CoreAIPrivacyRulesManaging", "CoreRemoteProviderConfiguring"
            ],
            "AI"
        ),
        BridgeContractOwner(
            "CoreRepositoryOpening.swift",
            ["CoreEmptyRepositoryOpening", "CoreRepositoryTreeListing"],
            "RepositoryLifecycle"
        ),
        BridgeContractOwner("CoreSavedSearches.swift", ["CoreSavedSearchCRUD"], "Search"),
        BridgeContractOwner("CoreSyncConflictDetecting.swift", ["CoreSyncConflictDetecting"], "SyncConflicts"),
        BridgeContractOwner("CoreSyncConflictResolving.swift", ["CoreSyncConflictResolving"], "SyncConflicts")
    ]

    func testEveryAppOwnedBridgeProtocolHasAnExactReverseInventoryEntry() throws {
        let actual = try bridgeProtocolDeclarations()
        let expected = Set(inventory.flatMap { item in
            item.protocolNames.map { "Bridge/\(item.file)|\($0)" }
        })
        XCTAssertEqual(
            actual,
            expected,
            "Every App-owned Bridge protocol must declare its source path and owner before it can be retained."
        )
    }

    func testReverseInventoryDocumentsOwnershipAndExtractionCondition() {
        let incomplete = inventory.compactMap { item -> String? in
            guard !item.owner.isEmpty, !item.reason.isEmpty, !item.exitCondition.isEmpty else { return item.file }
            return nil
        }
        XCTAssertEqual(incomplete, [])
    }

    func testCoreBridgeConformancesResolveToLocalOrPackageContracts() throws {
        let localProtocols = Set(inventory.flatMap(\.protocolNames))
        let packageFiles = try [
            "AreaMatrixCoreContracts",
            "AreaMatrixCoreBridgeContract",
            "AreaMatrixCoreBridgeRuntime",
            "AreaMatrixUIFoundation",
            "AreaMatrixPlatformKit",
            "AreaMatrixFeatureLibrary",
            "AreaMatrixFeatureIngestion",
            "AreaMatrixFeatureOperation",
            "AreaMatrixFeatureSettings",
            "AreaMatrixFeatureAI"
        ].flatMap(packageSwiftFiles)
        let packageProtocols = try packageFiles.reduce(into: Set<String>()) { result, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            try result.formUnion(protocolNames(in: source))
        }
        let knownProtocols = localProtocols.union(packageProtocols)
        let featureOwnedProtocols = Set(featureOwnedConformanceInventory.map(\.protocolName))
        let unresolved = try coreBridgeConformances().subtracting(knownProtocols)
        XCTAssertEqual(
            unresolved,
            featureOwnedProtocols,
            "Feature-owned CoreBridge conformances are an exact migration inventory and cannot grow."
        )

        let productionPaths = try Set(productionSwiftFiles().map { relativeProductionPath(for: $0) })
        let missingFeatureProtocols = featureOwnedConformanceInventory
            .filter { !productionPaths.contains($0.declarationPath) }
            .map(\.protocolName)
        XCTAssertEqual(
            missingFeatureProtocols,
            []
        )
    }

    private func bridgeProtocolDeclarations() throws -> Set<String> {
        let bridgeFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0).hasPrefix("Bridge/")
        }
        return try bridgeFiles.reduce(into: Set<String>()) { result, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            let path = relativeProductionPath(for: file)
            try result.formUnion(protocolNames(in: source).map { "\(path)|\($0)" })
        }
    }

    private func coreBridgeConformances() throws -> Set<String> {
        let bridgeFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0).hasPrefix("Bridge/")
        }
        return try bridgeFiles.reduce(into: Set<String>()) { result, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            let expression = try NSRegularExpression(
                pattern: #"extension\s+CoreBridge\s*:\s*([^\{]+)\{"#,
                options: [.dotMatchesLineSeparators]
            )
            let range = NSRange(source.startIndex ..< source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let capture = Range(match.range(at: 1), in: source) else { continue }
                let names = source[capture].split(separator: ",").compactMap { component in
                    component.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first
                        .map(String.init)
                }
                result.formUnion(names)
            }
        }
    }

    private func protocolNames(in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(
            pattern: #"(?m)^(?:@[A-Za-z]+\s+)?(?:public\s+|internal\s+)?protocol\s+([A-Za-z_][A-Za-z0-9_]*)"#
        )
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[capture])
        })
    }
}

private struct FeatureOwnedBridgeConformance {
    let protocolName: String
    let declarationPath: String
    let owner: String
}

private struct BridgeContractOwner {
    let file: String
    let protocolNames: [String]
    let owner: String
    let reason: String
    let exitCondition: String

    init(_ file: String, _ protocolNames: [String], _ owner: String) {
        self.file = file
        self.protocolNames = protocolNames
        self.owner = owner
        reason = "Retained while its high-risk adapter or presentation semantics remain App-owned."
        exitCondition = "Move the value-only Sendable contract when its owning Feature target is extracted."
    }
}
