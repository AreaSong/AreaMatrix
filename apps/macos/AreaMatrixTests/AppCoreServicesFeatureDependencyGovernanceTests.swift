import XCTest

extension AppCoreServicesGovernanceTests {
    func testFeatureAndViewLayersDoNotReadAppCoreServicesDirectly() throws {
        let violations = try productionSwiftFiles()
            .filter {
                let path = relativeProductionPath(for: $0)
                return path.hasPrefix("Features/") || path.hasPrefix("Views/")
            }
            .flatMap { try sourceTermViolations(in: $0, terms: ["AppCoreServices."]) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature and View layers must receive dependencies from the App composition root rather than " +
                "reading AppCoreServices directly."
        )
    }

    func testFeatureLayersDoNotReadTheAppDependencyContainerDirectly() throws {
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0).hasPrefix("Features/") }
            .flatMap { try sourceTermViolations(in: $0, terms: ["AppDependencyContainer"]) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature defaults must resolve through their feature dependency namespace; the App container belongs " +
                "to the composition root and must not leak into feature code."
        )
    }

    func testFeatureDefaultsStayOwnedByFeatureNamespaces() throws {
        let allowedNamespacesByFeature: [String: Set<String>] = [
            "AI": ["AIFeatureDependencies", "SharedFeatureDependencies"],
            "FileActions": ["FileActionsFeatureDependencies", "SharedFeatureDependencies"],
            "Import": ["ImportFeatureDependencies", "SharedFeatureDependencies"],
            "MainList": ["MainListFeatureDependencies", "SharedFeatureDependencies"],
            "Onboarding": ["OnboardingFeatureDependencies", "SharedFeatureDependencies"],
            "Diagnostics": ["DiagnosticsFeatureDependencies"],
            "Search": ["SearchFeatureDependencies", "SharedFeatureDependencies"],
            "Settings": [
                "AIFeatureDependencies",
                "SettingsFeatureDependencies",
                "SharedFeatureDependencies",
                "SyncConflictsFeatureDependencies"
            ],
            "SyncConflicts": ["SharedFeatureDependencies", "SyncConflictsFeatureDependencies"]
        ]
        let dependencyPattern = #"\b[A-Za-z]+FeatureDependencies\.[A-Za-z0-9_]+"#
        var violations: [String] = []

        for (feature, allowedNamespaces) in allowedNamespacesByFeature {
            let featureFiles = try productionSwiftFiles().filter {
                relativeProductionPath(for: $0).hasPrefix("Features/\(feature)/")
            }
            let matches = try featureFiles.flatMap {
                try sourceRegexMatches(in: $0, pattern: dependencyPattern)
            }
            violations.append(contentsOf: matches.filter { match in
                let dependencyReference = match.split(separator: ":", maxSplits: 1).last.map(String.init) ?? match
                return !allowedNamespaces.contains { namespace in
                    dependencyReference.hasPrefix("\(namespace).")
                }
            })
        }

        XCTAssertEqual(
            violations.sorted(),
            [],
            "Feature defaults must remain owned by their feature namespace or the explicitly shared namespace."
        )
    }

    func testFeatureAndViewLayersDoNotConstructHiddenLiveDependencies() throws {
        let violations = try productionSwiftFiles()
            .filter {
                let path = relativeProductionPath(for: $0)
                return path.hasPrefix("Features/") || path.hasPrefix("Views/")
            }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: [
                        #"\bAppDependencyContainer\.live\b"#,
                        #"\bAppCoreServices\.[A-Za-z0-9_]+"#,
                        #"\bAppPlatformServices\.[A-Za-z0-9_]+"#,
                        #"\b(?:[A-Za-z]+FeatureDependencies|SharedFeatureDependencies)\.live\b"#
                    ].joined(separator: "|")
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature and View layers must not construct hidden live dependencies; all runtime defaults belong " +
                "to the App composition root and must cross an explicit feature scope."
        )
    }

    func testFeatureManifestOwnershipIsDistributedAndComposedByApp() throws {
        let providerByFeature: [String: (fileStem: String, typeName: String)] = [
            "AI": ("AIFeatureManifestProvider", "AIFeatureManifestProvider"),
            "CommandPalette": ("CommandPaletteFeatureManifestProvider", "CommandPaletteFeatureManifestProvider"),
            "Detail": ("DetailFeatureManifestProvider", "DetailFeatureManifestProvider"),
            "Diagnostics": ("DiagnosticsFeatureManifestProvider", "DiagnosticsFeatureManifestProvider"),
            "FileActions": ("FileActionsFeatureManifestProvider", "FileActionsFeatureManifestProvider"),
            "Import": ("ImportFeatureManifestProvider", "ImportFeatureManifestProvider"),
            "MainList": ("MainListFeatureManifestProvider", "MainListFeatureManifestProvider"),
            "Onboarding": ("OnboardingFeatureManifestProvider", "OnboardingFeatureManifestProvider"),
            "RepositoryLifecycle": (
                "RepositoryLifecycleFeatureManifestProvider",
                "RepositoryLifecycleManifestProvider"
            ),
            "Search": ("SearchFeatureManifestProvider", "SearchFeatureManifestProvider"),
            "Settings": ("SettingsFeatureManifestProvider", "SettingsFeatureManifestProvider"),
            "SyncConflicts": ("SyncConflictsFeatureManifestProvider", "SyncConflictsFeatureManifestProvider")
        ]
        let registryFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureManifest.swift"
        })
        let registrySource = try String(contentsOf: registryFile, encoding: .utf8)

        XCTAssertFalse(
            registrySource.contains("FeatureManifest("),
            "The App registry should compose feature-owned manifests instead of owning their metadata."
        )

        for (feature, provider) in providerByFeature {
            let providerPath = "Features/\(feature)/\(provider.fileStem).swift"
            let providerFile = try XCTUnwrap(productionSwiftFiles().first {
                relativeProductionPath(for: $0) == providerPath
            })
            let providerSource = try String(contentsOf: providerFile, encoding: .utf8)
            XCTAssertTrue(providerSource.contains("enum \(provider.typeName): FeatureManifestProvider"))
            XCTAssertTrue(registrySource.contains("\(provider.typeName).manifest"))
        }
    }
}
