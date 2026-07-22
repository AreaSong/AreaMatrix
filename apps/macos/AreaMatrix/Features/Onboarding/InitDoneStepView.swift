import SwiftUI

struct InitDoneStepView: View {
    let result: RepositoryInitializationResult
    let errorMapping: CoreErrorMappingSnapshot?
    let onOpenRepository: () -> Void
    let onOpenInFinder: () async -> Void

    @State private var isOpeningFinder = false

    var body: some View {
        VStack(alignment: .center, spacing: 28) {
            header

            VStack(spacing: 20) {
                pathBox
                summarySection
                openErrorSection
            }
            .frame(maxWidth: 440)

            footer
        }
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
    }

    private var header: some View {
        AreaMatrixStepHeader(
            systemImage: "checkmark.circle.fill",
            tint: AreaMatrixTheme.Colors.emerald,
            title: L10n.string("onboarding.done.title"),
            subtitle: L10n.string("onboarding.done.subtitle")
        )
    }

    private var pathBox: some View {
        AreaMatrixPathBox(path: result.repoPath)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summaryItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
        }
    }

    @ViewBuilder
    private var openErrorSection: some View {
        if let errorMapping {
            TintedOutlinedStatusBanner(tint: .red) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.string("onboarding.done.cannotOpen"), systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(errorMapping.userMessage)
                    Text(errorMapping.suggestedAction)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.string("onboarding.done.openInFinder")) {
                Task {
                    await openInFinder()
                }
            }
            .buttonStyle(AreaMatrixSecondaryButtonStyle())
            .disabled(isOpeningFinder)

            if isOpeningFinder {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button(action: onOpenRepository) {
                Text(errorMapping == nil
                    ? L10n.string("onboarding.done.openRepository")
                    : L10n.string("onboarding.done.retry"))
                    .font(.body.weight(.medium))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(AreaMatrixPrimaryButtonStyle(accent: AreaMatrixTheme.Colors.emerald))
            .controlSize(.large)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    @MainActor
    private func openInFinder() async {
        guard !isOpeningFinder else { return }

        isOpeningFinder = true
        defer {
            isOpeningFinder = false
        }
        await onOpenInFinder()
    }

    private var summaryItems: [String] {
        switch result.mode {
        case .createEmpty:
            [
                L10n.string("onboarding.done.defaultCategoriesCreated"),
                L10n.string("onboarding.done.localIndexCreated"),
                L10n.string("onboarding.done.automaticOverviewEnabled")
            ]
        case .adoptExisting:
            [
                L10n.string("onboarding.done.localIndexBuilt"),
                L10n.string("onboarding.done.existingFilesScanned"),
                L10n.string("onboarding.done.structurePreserved"),
                L10n.string("onboarding.done.internalOverviewGenerated")
            ]
        }
    }
}
