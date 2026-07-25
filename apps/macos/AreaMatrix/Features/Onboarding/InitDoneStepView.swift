import SwiftUI

struct InitDoneStepView: View {
    let result: RepositoryInitializationResult
    let errorMapping: CoreErrorMappingSnapshot?
    let onOpenRepository: () -> Void
    let onOpenInFinder: () async -> Void

    @State private var isOpeningFinder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            header

            VStack(alignment: .leading, spacing: 24) {
                pathBox
                summarySection
                openErrorSection
            }

            Spacer()
            footer
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                AreaMatrixLucideIcon(name: .checkCircle, lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(AreaMatrixTheme.Colors.emerald)
                    .background(
                        Circle()
                            .fill(AreaMatrixTheme.Colors.emerald.opacity(0.1))
                            .frame(width: 48, height: 48)
                    )
                Text("SUCCESS")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(AreaMatrixTheme.Colors.emerald)
                    .tracking(6)
            }
            .padding(.bottom, 8)
            
            Text(L10n.string("onboarding.done.title"))
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Text(L10n.string("onboarding.done.subtitle"))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var pathBox: some View {
        AreaMatrixPathBox(path: result.repoPath)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(summaryItems.enumerated()), id: \.element) { index, item in
                    HStack(spacing: 10) {
                        AreaMatrixLucideIcon(name: .checkCircle, lineWidth: 2)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(AreaMatrixTheme.Colors.emerald)
                        Text(item)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.04),
                        value: summaryItems
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                    )
            )
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
            HoverableGhostButton(
                action: { Task { await openInFinder() } },
                icon: .folder,
                title: L10n.string("onboarding.done.openInFinder")
            )
            .disabled(isOpeningFinder)

            if isOpeningFinder {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            HoverableCapsuleButton(
                action: onOpenRepository,
                title: errorMapping == nil ? L10n.string("onboarding.done.openRepository") : L10n.string("onboarding.done.retry"),
                isDisabled: false,
                accent: AreaMatrixTheme.Colors.emerald
            )
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct HoverableGhostButton: View {
    let action: () -> Void
    let icon: AreaMatrixLucideIcon.IconName?
    let title: String
    @State private var isHovered = false
    
    var body: some View {
        AreaMatrixGhostButton(isHovered: isHovered, action: action) {
            HStack(spacing: 6) {
                if let icon {
                    AreaMatrixLucideIcon(name: icon, lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
                Text(title)
            }
        }
        .onHover { hovering in
            isHovered = hovering
            AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
        }
    }
}

private struct HoverableCapsuleButton: View {
    let action: () -> Void
    let title: String
    let isDisabled: Bool
    let accent: Color
    @State private var isHovered = false
    
    var body: some View {
        AreaMatrixCapsuleButton(accent: accent, isHovered: isHovered, action: action) {
            Text(title)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
                AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
            }
        }
    }
}

extension InitDoneStepView {
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
