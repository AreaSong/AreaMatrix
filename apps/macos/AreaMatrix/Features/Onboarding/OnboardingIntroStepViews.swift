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
    @Binding var pathText: String

    @FocusState private var isInputFocused: Bool
    @State private var isDropTargeted = false

    let errorMessage: String?
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
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.blue, lineWidth: isDropTargeted ? 3 : 0)
                .opacity(isDropTargeted ? 0.8 : 0)
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
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
        VStack(alignment: .center, spacing: 14) {
            ZStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(.blue)
                    .blur(radius: 20)
                    .opacity(0.5)

                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 8)

            Text("选择资料库位置")
                .font(.system(size: 32, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)

            Text("资料库是一个普通文件夹，你可以随时在 Finder 中访问它。\n接管已有目录不会移动、重命名或删除你的任何原文件。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .opacity(isInputFocused ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isInputFocused)
    }

    private var pathSelection: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                TextField("Repository path", text: $pathText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .accessibilityLabel("Repository path")
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
                Label(errorMessage, systemImage: "exclamationmark.triangle")
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
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading repository settings...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConfigurationErrorView: View {
    let failure: ConfigLoadFailure
    let onRetry: () -> Void
    let onStartSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(failure.title, systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
            Text(failure.message)
                .foregroundStyle(.secondary)
            Text(failure.recoveryAction)
                .foregroundStyle(.secondary)
            HStack {
                Button("Start setup", action: onStartSetup)
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(48)
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .center)
    }
}
