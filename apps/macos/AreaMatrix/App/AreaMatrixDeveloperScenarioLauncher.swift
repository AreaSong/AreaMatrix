import SwiftUI

#if DEBUG
@MainActor
struct AreaMatrixDeveloperScenarioLauncher: View {
    @EnvironmentObject private var localizer: AppLocalizer

    @State private var selectedScenario: AreaMatrixDeveloperScenario
    @State private var selectedTheme: AreaMatrixPreviewTheme
    @State private var selectedLanguage: AreaMatrixPreviewLanguage
    @State private var selectedViewport: AreaMatrixPreviewViewport

    init(initialConfiguration: AreaMatrixDeveloperScenarioConfiguration = .launcher) {
        _selectedScenario = State(initialValue: initialConfiguration.scenario == .launcher
            ? .uiCatalog
            : initialConfiguration.scenario)
        _selectedTheme = State(initialValue: initialConfiguration.theme)
        _selectedLanguage = State(initialValue: initialConfiguration.language)
        _selectedViewport = State(initialValue: initialConfiguration.viewport == .wide
            ? .standard
            : initialConfiguration.viewport)
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

            VStack(alignment: .leading, spacing: 12) {
                canvasHeader
                ScrollView([.horizontal, .vertical]) {
                    AreaMatrixDeveloperScenarioContent(scenario: selectedScenario)
                        .frame(width: selectedViewport.size.width, height: selectedViewport.size.height)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                        .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
                        .padding(24)
                }
                .background(Color.secondary.opacity(0.08))
            }
            .padding(18)
        }
        .background(.background)
        .preferredColorScheme(selectedTheme.colorScheme)
        .accessibilityIdentifier("developer.scenarioLauncher")
        .onAppear(perform: applyLanguage)
        .onChange(of: selectedLanguage) { _, _ in applyLanguage() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(developerText("Scenario Launcher"))
                    .font(.title2.bold())
                Text(developerText("Browse deterministic UI states without repository or Core I/O."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker(developerText("Scenario"), selection: $selectedScenario) {
                ForEach(launchableScenarios) { scenario in
                    Text(developerText("\(scenario.feature) · \(scenario.title)"))
                        .tag(scenario)
                }
            }
            .labelsHidden()

            VStack(alignment: .leading, spacing: 10) {
                developerLabel("Theme")
                Picker(developerText("Theme"), selection: $selectedTheme) {
                    ForEach(AreaMatrixPreviewTheme.allCases) { theme in
                        Text(developerText(theme.rawValue.capitalized)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                developerLabel("Language")
                Picker(developerText("Language"), selection: $selectedLanguage) {
                    ForEach(AreaMatrixPreviewLanguage.allCases) { language in
                        Text(developerText(language.rawValue)).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                developerLabel("Viewport")
                Picker(developerText("Viewport"), selection: $selectedViewport) {
                    ForEach(AreaMatrixPreviewViewport.allCases) { viewport in
                        Text(developerText(viewport.rawValue.capitalized)).tag(viewport)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                developerLabel("Coverage")
                LabeledContent(developerText("Feature"), value: developerText(selectedScenario.feature))
                LabeledContent(developerText("State"), value: developerText(selectedScenario.stateKind.rawValue))
                LabeledContent(
                    developerText("Size"),
                    value: developerText(
                        "\(Int(selectedViewport.size.width)) × \(Int(selectedViewport.size.height))"
                    )
                )
                LabeledContent(
                    developerText("Full pages"),
                    value: developerText(
                        "\(AreaMatrixDeveloperSurfaceInventory.covered.count)/" +
                            "\(AreaMatrixDeveloperSurfaceInventory.all.count)"
                    )
                )
            }
            .font(.caption)

            Spacer()

            Text(developerText(runCommand))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("developer.scenarioLauncher.command")
        }
        .padding(18)
    }

    private var canvasHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(developerText(selectedScenario.title))
                    .font(.title3.bold())
                Text(developerText(selectedScenario.rawValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(developerText(selectedScenario.stateKind.rawValue.uppercased()))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateTint.opacity(0.15), in: Capsule())
                .foregroundStyle(stateTint)
        }
    }

    private var launchableScenarios: [AreaMatrixDeveloperScenario] {
        AreaMatrixDeveloperScenario.allCases.filter { $0 != .launcher }
    }

    private var runCommand: String {
        "./dev run macos --scenario \(selectedScenario.rawValue) "
            + "--theme \(selectedTheme.rawValue) "
            + "--locale \(selectedLanguage.rawValue) "
            + "--viewport \(selectedViewport.rawValue)"
    }

    private var stateTint: Color {
        switch selectedScenario.stateKind {
        case .success: .green
        case .loading: .blue
        case .empty, .disabled, .stale: .orange
        case .failed: .red
        case .blocked, .unavailable: .purple
        }
    }

    private func developerLabel(_ value: String) -> some View {
        Text(developerText(value))
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    private func developerText(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .technicalIdentifier))
    }

    private func applyLanguage() {
        localizer.apply(
            selectedLanguage.appLanguage,
            preferredLanguages: [selectedLanguage.rawValue]
        )
    }
}
#endif
