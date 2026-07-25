import SwiftUI

struct ValidatePathFooter: View {
    let isInitializedRepository: Bool
    let isValidating: Bool
    let canContinue: Bool
    let primaryActionTitle: String
    let showsCancel: Bool
    let onBack: () -> Void
    let onCancel: () -> Void
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack {
            if isInitializedRepository {
                existingRepositoryFooter
            } else {
                defaultFooter
            }
        }
        .disabled(isValidating)
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var defaultFooter: some View {
        HoverableGhostButton(
            action: onBack,
            icon: .arrowRight, // 这里可以不用，或者用 .arrowLeft，暂时不用图标
            title: L10n.string("onboarding.validate.back")
        )

        if showsCancel {
            HoverableGhostButton(
                action: onCancel,
                icon: .xCircle,
                title: L10n.string("onboarding.validate.cancel")
            )
        }

        Spacer()

        HoverableGhostButton(
            action: onChangePath,
            icon: .folder,
            title: L10n.string("onboarding.validate.change")
        )

        HoverableGhostButton(
            action: onRetry,
            icon: .refreshCcw,
            title: L10n.string("onboarding.validate.retry")
        )

        primaryButton
    }

    private var existingRepositoryFooter: some View {
        Group {
            HoverableGhostButton(
                action: onBack,
                icon: nil,
                title: L10n.string("onboarding.validate.back")
            )

            Spacer()

            HoverableGhostButton(
                action: onChangePath,
                icon: .folder,
                title: L10n.string("onboarding.validate.changeLocation")
            )

            primaryButton
        }
    }

    private var primaryButton: some View {
        HoverableCapsuleButton(
            action: onContinue,
            title: primaryActionTitle,
            isDisabled: !canContinue,
            accent: AreaMatrixTheme.Colors.teal
        )
        .keyboardShortcut(.defaultAction)
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
