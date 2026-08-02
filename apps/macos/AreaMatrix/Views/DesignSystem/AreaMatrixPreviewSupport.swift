import SwiftUI

struct AreaMatrixPreviewScenario<Value>: Identifiable {
    let id: String
    let title: AppDisplayText
    let value: Value
}

struct AreaMatrixLanguagePreviewFixture: Identifiable {
    let id: String
    let interfaceLanguage: AppLanguage
    let contentLanguage: RepositoryContentLanguage
    let interfaceIdentifier: String
    let contentIdentifier: String
}

enum AreaMatrixPreviewFixtures {
    static let repositoryPath = "/Users/example/AreaMatrix Library"
    static let longRepositoryPath =
        "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/AreaMatrix/Very Long Repository Name"

    static let statusScenarios = [
        AreaMatrixPreviewScenario(
            id: "ready",
            title: L10n.verbatim("Ready", reason: .technicalIdentifier),
            value: Color.green
        ),
        AreaMatrixPreviewScenario(
            id: "warning",
            title: L10n.verbatim("Warning", reason: .technicalIdentifier),
            value: Color.orange
        ),
        AreaMatrixPreviewScenario(
            id: "error",
            title: L10n.verbatim("Error", reason: .technicalIdentifier),
            value: Color.red
        )
    ]

    static let languageCombinations = [
        AreaMatrixLanguagePreviewFixture(
            id: "en-en",
            interfaceLanguage: .en,
            contentLanguage: .en,
            interfaceIdentifier: "en",
            contentIdentifier: "en"
        ),
        AreaMatrixLanguagePreviewFixture(
            id: "en-zh-Hans",
            interfaceLanguage: .en,
            contentLanguage: .zhHans,
            interfaceIdentifier: "en",
            contentIdentifier: "zh-Hans"
        ),
        AreaMatrixLanguagePreviewFixture(
            id: "zh-Hans-en",
            interfaceLanguage: .zhHans,
            contentLanguage: .en,
            interfaceIdentifier: "zh-Hans",
            contentIdentifier: "en"
        ),
        AreaMatrixLanguagePreviewFixture(
            id: "zh-Hans-zh-Hans",
            interfaceLanguage: .zhHans,
            contentLanguage: .zhHans,
            interfaceIdentifier: "zh-Hans",
            contentIdentifier: "zh-Hans"
        )
    ]

    static let permissionFailure = CoreErrorMappingSnapshot(
        kind: .permissionDenied,
        userMessage: L10n.message("core.error.PermissionDenied.message"),
        severity: .high,
        suggestedAction: L10n.message("core.error.PermissionDenied.action"),
        recoverability: .userActionRequired,
        rawContext: longRepositoryPath
    )

    static let iCloudRows = [
        fileRow(index: 1, status: .iCloudPlaceholder(path: "inbox/annual-report.pdf")),
        fileRow(index: 2, status: .iCloudPlaceholder(path: "inbox/research-notes.md"))
    ]

    static let syncConflict = SyncConflictSnapshot(
        conflictID: "developer-sync-conflict",
        conflictType: .sameNameDifferentContent,
        severity: .high,
        status: .needsReview,
        primaryPath: "docs/report.pdf",
        affectedFiles: [
            SyncConflictAffectedFileSnapshot(
                path: "docs/report.pdf",
                fileID: 42,
                role: .existing,
                sizeBytes: 2048,
                modifiedAt: 1_778_738_400,
                hashSha256: "abcdef1234567890",
                sourcePlatform: "macOS"
            ),
            SyncConflictAffectedFileSnapshot(
                path: "docs/report (Windows conflict).pdf",
                fileID: 43,
                role: .incoming,
                sizeBytes: 2112,
                modifiedAt: 1_778_738_500,
                hashSha256: "fedcba9876543210",
                sourcePlatform: "Windows"
            )
        ],
        versionCount: 2,
        sourceProvider: "OneDrive",
        detectedAt: 1_778_738_600,
        summary: "Two versions of docs/report.pdf need review."
    )

    static func fileRows(count: Int) -> [ImportFolderPreviewRow] {
        (0 ..< count).map { index in
            fileRow(index: index, status: rowStatus(index: index))
        }
    }

    private static func fileRow(
        index: Int,
        status: ImportFolderPreviewRowStatus
    ) -> ImportFolderPreviewRow {
        let filename = String(format: "document-%03d.pdf", index + 1)
        let rootURL = URL(fileURLWithPath: "/developer-preview")
        return ImportFolderPreviewRow(
            fileURL: rootURL.appendingPathComponent(filename),
            rootURL: rootURL,
            originalName: filename,
            relativePath: "incoming/\(filename)",
            sizeBytes: Int64((index + 1) * 1024),
            predictedCategory: index.isMultiple(of: 5) ? "finance" : "docs",
            suggestedName: filename,
            status: status
        )
    }

    private static func rowStatus(index: Int) -> ImportFolderPreviewRowStatus {
        switch index % 12 {
        case 7:
            .duplicate(existingPath: "docs/document.pdf", strategy: .keepBoth, isReplaceConfirmed: false)
        case 8:
            .nameConflict(existingPath: "docs/document.pdf", resolution: .keepBoth)
        case 9:
            .iCloudPlaceholder(path: "incoming/document.pdf")
        case 10:
            .blocked(L10n.display("core.error.PermissionDenied.message"))
        case 11:
            .error(L10n.display("import.preview.categoryUnavailable"))
        default:
            .ready(reason: index.isMultiple(of: 2) ? .extension : .keyword, confidencePercent: 92)
        }
    }
}

struct AreaMatrixPreviewSurface<Content: View>: View {
    let scene: AreaMatrixAmbientScene
    let content: Content

    init(
        scene: AreaMatrixAmbientScene = .home,
        @ViewBuilder content: () -> Content
    ) {
        self.scene = scene
        self.content = content()
    }

    var body: some View {
        ZStack {
            AreaMatrixAmbientBackground(scene: scene, parallax: .zero, strength: .subdued)
                .ignoresSafeArea()
            content
        }
        .frame(width: 900, height: 680)
    }
}

#if DEBUG
@MainActor
private struct AreaMatrixDeveloperPreviewHarness<Content: View>: View {
    @StateObject private var localizer: AppLocalizer
    @StateObject private var languageStore: AppLanguageStore

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        let runtime = AppLanguageRuntime.shared
        let localizer = AppLocalizer(runtime: runtime)
        let defaults = UserDefaults(suiteName: "AreaMatrix.DeveloperPreview") ?? .standard
        _localizer = StateObject(wrappedValue: localizer)
        _languageStore = StateObject(wrappedValue: AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            localizer: localizer,
            initialLanguageOverride: .en
        ))
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(languageStore)
            .environmentObject(localizer)
            .environment(\.locale, Locale(identifier: localizer.resourceLocaleIdentifier))
    }
}

#Preview("UI Catalog — Light") {
    AreaMatrixDeveloperPreviewHarness {
        AreaMatrixPreviewSurface {
            AreaMatrixUICatalog()
        }
        .preferredColorScheme(.light)
    }
}

#Preview("UI Catalog — Dark") {
    AreaMatrixDeveloperPreviewHarness {
        AreaMatrixPreviewSurface {
            AreaMatrixUICatalog()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Scenario Launcher") {
    AreaMatrixDeveloperPreviewHarness {
        AreaMatrixDeveloperScenarioView(configuration: .launcher)
    }
}
#endif
