import AreaMatrixUIFoundation
import SwiftUI

@MainActor
struct AreaMatrixUICatalog: View {
    @State private var selectedStatus = "ready"
    @State private var toggleValue = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                catalogHeader
                colors
                languageMatrix
                controls
                statusComponents
                pathComponents
            }
            .padding(32)
        }
        .frame(minWidth: 760, minHeight: 560)
        .accessibilityIdentifier("developer.uiCatalog")
    }

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(developerText("AreaMatrix UI Catalog"))
                .font(.largeTitle.bold())
            Text(developerText("Reusable component states without launching repositories or Core services."))
                .foregroundStyle(.secondary)
        }
    }

    private var colors: some View {
        catalogSection("Color Tokens") {
            HStack(spacing: 12) {
                colorToken("Teal", AreaMatrixTheme.Colors.teal)
                colorToken("Gold", AreaMatrixTheme.Colors.gold)
                colorToken("Coral", AreaMatrixTheme.Colors.coral)
                colorToken("Purple", AreaMatrixTheme.Colors.purple)
                colorToken("Emerald", AreaMatrixTheme.Colors.emerald)
            }
        }
    }

    private var controls: some View {
        catalogSection("Controls") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button(developerText("Primary Action")) {}
                        .buttonStyle(AreaMatrixPrimaryButtonStyle())
                    Button(developerText("Secondary Action")) {}
                    Button(developerText("Disabled")) {}
                        .disabled(true)
                }
                Picker(developerText("Status"), selection: $selectedStatus) {
                    ForEach(AreaMatrixPreviewFixtures.statusScenarios) { scenario in
                        Text(L10n.resolve(scenario.title)).tag(scenario.id)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(developerText("Enabled state"), isOn: $toggleValue)
            }
        }
    }

    private var languageMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(developerText("Language Matrix"))
                .font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(
                    Array(AreaMatrixPreviewFixtures.languageCombinations.enumerated()),
                    id: \.element.id
                ) { index, fixture in
                    AreaMatrixLanguageMatrixRow(fixture: fixture)
                    if index < AreaMatrixPreviewFixtures.languageCombinations.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusComponents: some View {
        catalogSection("Status Components") {
            VStack(spacing: 12) {
                TintedStatusBanner(tint: .green) {
                    Label(developerText("Ready state"), systemImage: "checkmark.circle.fill")
                }
                TintedOutlinedStatusBanner(tint: .orange) {
                    Label(developerText("Warning state"), systemImage: "exclamationmark.triangle.fill")
                }
                ReasonStatusCard(
                    badge: developerText("ERROR"),
                    badgeTint: .red,
                    accessibilityIdentifier: "developer.uiCatalog.reasonCard",
                    badgeAccessibilityIdentifier: "developer.uiCatalog.reasonBadge"
                ) {
                    Text(developerText("Recoverable error"))
                        .font(.headline)
                } message: {
                    Text(developerText("The component keeps the reason and recovery action visually grouped."))
                        .foregroundStyle(.secondary)
                } actions: {
                    Button(developerText("Retry")) {}
                }
            }
        }
    }

    private var pathComponents: some View {
        catalogSection("Paths and Chips") {
            VStack(alignment: .leading, spacing: 12) {
                AreaMatrixPathBox(path: AreaMatrixPreviewFixtures.repositoryPath, alignment: .leading)
                AreaMatrixPathBox(
                    path: AreaMatrixPreviewFixtures.longRepositoryPath,
                    style: .plain,
                    alignment: .leading
                )
                HStack {
                    NeutralCapsuleChip { Text(developerText("Default")) }
                    NeutralCapsuleChip(backgroundOpacity: 0.2) { Text(developerText("Selected")) }
                }
            }
        }
    }

    private func catalogSection(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(developerText(title))
                .font(.title3.bold())
            content()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorToken(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 76, height: 52)
            Text(developerText(name))
                .font(.caption)
        }
    }

    private func developerText(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .technicalIdentifier))
    }
}

@MainActor
private struct AreaMatrixLanguageMatrixRow: View {
    let fixture: AreaMatrixLanguagePreviewFixture

    @StateObject private var localizer: AppLocalizer

    init(fixture: AreaMatrixLanguagePreviewFixture) {
        self.fixture = fixture
        let runtime = AppLanguageRuntime(selection: fixture.interfaceLanguage)
        _localizer = StateObject(wrappedValue: AppLocalizer(runtime: runtime))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Text(fixture.id)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 180, alignment: .leading)
            languageColumn(
                title: localizer.string("settings.language.interface.title"),
                value: localizer.resolve(fixture.interfaceLanguage.displayMessage),
                identifier: fixture.interfaceIdentifier
            )
            languageColumn(
                title: localizer.string("settings.language.content.title"),
                value: localizer.resolve(fixture.contentLanguage.displayMessage),
                identifier: fixture.contentIdentifier
            )
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("developer.uiCatalog.language.\(fixture.id)")
    }

    private func languageColumn(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
            Text(identifier)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
