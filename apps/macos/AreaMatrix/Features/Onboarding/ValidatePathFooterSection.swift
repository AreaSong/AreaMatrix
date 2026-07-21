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
        Button(action: onBack) { Text(String(localized: "onboarding.validate.back")).font(.body.weight(.medium)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

        if showsCancel {
            Button(action: onCancel) { Text(String(localized: "onboarding.validate.cancel")).font(.body.weight(.medium)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }

        Spacer()

        Button(action: onChangePath) { Text(String(localized: "onboarding.validate.change")) }
            .controlSize(.large)

        Button(action: onRetry) { Text(String(localized: "onboarding.validate.retry")) }
            .controlSize(.large)

        primaryButton
    }

    private var existingRepositoryFooter: some View {
        Group {
            Button(action: onBack) { Text(String(localized: "onboarding.validate.back")).font(.body.weight(.medium)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onChangePath) { Text(String(localized: "onboarding.validate.changeLocation")) }
                .controlSize(.large)

            primaryButton
        }
    }

    private var primaryButton: some View {
        Button(action: onContinue) {
            Text(primaryActionTitle)
                .font(.body.weight(.medium))
                .frame(minWidth: 80)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canContinue)
    }
}
