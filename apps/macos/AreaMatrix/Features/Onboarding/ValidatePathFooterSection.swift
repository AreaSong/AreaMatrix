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
        Button(action: onBack) { Text("返回").font(.body.weight(.medium)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

        if showsCancel {
            Button(action: onCancel) { Text("取消").font(.body.weight(.medium)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }

        Spacer()

        Button(action: onChangePath) { Text("更改") }
            .controlSize(.large)

        Button(action: onRetry) { Text("重试") }
            .controlSize(.large)

        primaryButton
    }

    private var existingRepositoryFooter: some View {
        Group {
            Button(action: onBack) { Text("返回").font(.body.weight(.medium)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onChangePath) { Text("更改位置") }
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
