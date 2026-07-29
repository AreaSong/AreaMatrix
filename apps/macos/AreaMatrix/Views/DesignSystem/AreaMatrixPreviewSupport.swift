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
#Preview("UI Catalog — Light") {
    AreaMatrixPreviewSurface {
        AreaMatrixUICatalog()
    }
    .preferredColorScheme(.light)
}

#Preview("UI Catalog — Dark") {
    AreaMatrixPreviewSurface {
        AreaMatrixUICatalog()
    }
    .preferredColorScheme(.dark)
}
#endif
