import SwiftUI

#if DEBUG
@MainActor
struct DeveloperDiagnosticsScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .diagnosticsConsole:
            DiagnosticsConsoleView(
                events: DeveloperDiagnosticsScenarioFixture.events,
                catalog: DeveloperDiagnosticsScenarioFixture.catalog
            )
            .background(.background)
        case .diagnosticsPackagePreview:
            DiagnosticsPackagePreviewSheet(
                summary: DeveloperDiagnosticsScenarioFixture.packagePreviewSummary,
                onCancel: {},
                onExport: {}
            )
            .background(.background)
        case .diagnosticsSettings:
            DeveloperDiagnosticsSettingsScenario()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperDiagnosticsSettingsScenario: View {
    @State private var hasLoaded = false

    private let hub: ObservabilityHub
    private let model: DiagnosticsSettingsModel

    init() {
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(
                inMemory: DeveloperDiagnosticsScenarioFixture.configuration
            ),
            rootURL: nil,
            sessionID: DeveloperDiagnosticsScenarioFixture.sessionID,
            expectedCoreBuildContext: DeveloperDiagnosticsScenarioFixture.coreBuildContext
        )
        let runtime = ObservabilityRuntimeAssembly(
            hub: hub,
            core: DeveloperDiagnosticsCoreFixture(),
            resourceIdentityProvider: .shared,
            sessionID: DeveloperDiagnosticsScenarioFixture.sessionID,
            scheduler: .live
        )
        self.hub = hub
        model = DiagnosticsSettingsModel(
            runtime: runtime,
            incidentManager: DeveloperDiagnosticsIncidentFixture(),
            packagePreviewer: DeveloperDiagnosticsPackagePreviewer(),
            packageHandler: DeveloperDiagnosticsPackageHandler(),
            repositoryURL: nil,
            nowMilliseconds: { 1_778_738_500_000 },
            sessionID: DeveloperDiagnosticsScenarioFixture.sessionID
        )
    }

    var body: some View {
        DiagnosticsSettingsPane(model: model, loadsAutomatically: false)
            .background(.background)
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                for input in DeveloperDiagnosticsScenarioFixture.semanticInputs {
                    await hub.recordSemanticAction(input)
                }
                await model.load()
            }
    }
}
#endif
