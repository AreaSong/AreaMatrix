import SwiftUI
import UniformTypeIdentifiers

struct SettingsRepositoryReturnView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Repository settings", systemImage: "gearshape")
        } description: {
            Text("Repository change was cancelled before opening a new repository.")
        }
    }
}

struct ChoosePathStepView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @Binding var pathText: String

    @FocusState private var isInputFocused: Bool
    @State private var isDropTargeted = false

    let errorMessage: LocalizedMessage?
    let isValidating: Bool
    let canContinue: Bool
    let onBack: () -> Void
    let onChoose: () -> Void
    let onUseDefault: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 32) {
            header

            VStack(spacing: 24) {
                pathSelection
            }
            .frame(maxWidth: 440)

            footer
        }
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AreaMatrixTheme.Colors.tealBright, lineWidth: isDropTargeted ? 3 : 0)
                .opacity(isDropTargeted ? 0.8 : 0)
                .animation(.areaMatrixQuickFade, value: isDropTargeted)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            if let provider = providers
                .first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            pathText = url.path
                        }
                    }
                }
                return true
            }
            return false
        }
    }

    private var header: some View {
        AreaMatrixStepHeader(
            title: L10n.string("onboarding.location.title"),
            subtitle: L10n.string("onboarding.location.subtitle")
        ) {
            ZStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(AreaMatrixTheme.Colors.tealBright)
                    .blur(radius: 20)
                    .opacity(0.5)

                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(AreaMatrixTheme.Colors.tealBright)
            }
        }
        .opacity(isInputFocused ? 0.4 : 1.0)
        .animation(.areaMatrixThemeToggle, value: isInputFocused)
    }

    private var pathSelection: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                TextField("Repository path", text: $pathText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .areaMatrixGlassCard(cornerRadius: 10)
                    .accessibilityLabel(L10n.string("Repository path"))
                    .disabled(isValidating)

                Button(action: onChoose) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 24)
                }
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
                .controlSize(.large)
                .disabled(isValidating)
            }

            if let errorMessage {
                Label(localizer.resolve(errorMessage), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if pathText.trimmingCharacters(in: .whitespacesAndNewlines) != "~/AreaMatrix/",
                      pathText.trimmingCharacters(in: .whitespacesAndNewlines) != (NSHomeDirectory() + "/AreaMatrix/") {
                Button(action: onUseDefault) {
                    Text("恢复推荐默认路径: ~/AreaMatrix/")
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .disabled(isValidating)
            } else {
                Label("系统推荐路径", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "escape")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.6)
                    Text("返回")
                }
            }
            .buttonStyle(AreaMatrixSecondaryButtonStyle())
            .disabled(isValidating)

            Spacer()

            if isValidating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button(action: onContinue) {
                HStack(spacing: 4) {
                    Text("继续")
                    Image(systemName: "return")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.6)
                }
                .frame(minWidth: 80)
            }
            .buttonStyle(AreaMatrixPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(!canContinue)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }
}

struct LoadingConfigurationView: View {
    @State private var entered = false

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(AreaMatrixTheme.Colors.tealBright)
            Text("Loading repository settings...")
                .font(.headline)
        }
        .areaMatrixGlassContentPanel(width: 420, padding: 36)
        .areaMatrixDelayedEntrance(isVisible: entered, delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .onAppear { entered = true }
    }
}

struct ConfigurationErrorView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let failure: ConfigLoadFailure
    let onRetry: () -> Void
    let onStartSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AreaMatrixStepHeader(
                systemImage: "exclamationmark.triangle",
                tint: AreaMatrixTheme.Colors.coral,
                title: localizer.resolve(failure.title),
                subtitle: localizer.resolve(failure.message)
            )
            Text(localizer.resolve(failure.recoveryAction))
                .foregroundStyle(.secondary)
            HStack {
                Button("Start setup", action: onStartSetup)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(AreaMatrixPrimaryButtonStyle())
            }
        }
        .areaMatrixGlassContentPanel(width: 560)
        .areaMatrixPageContentEntrance()
    }
}
