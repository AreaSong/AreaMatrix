import SwiftUI

struct MainLoadingView: View {
    let state: MainLoadingState
    let onCancelOpening: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView(state.accessibilityStatusText)
                .controlSize(.large)
                .accessibilityLabel(state.accessibilityStatusText)
            Text("正在打开资料库...")
                .font(.title2.weight(.semibold))
            pathBox
            adoptScanSection
            safetyText
            Button("Cancel opening", action: onCancelOpening)
                .accessibilityHint("Cancel opening returns to folder validation and does not modify user files.")
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var pathBox: some View {
        Text(state.repoPath)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var adoptScanSection: some View {
        if let status = state.adoptStatusText {
            VStack(alignment: .leading, spacing: 6) {
                Text(status)
                    .font(.headline)
                if let progress = state.adoptProgressText {
                    Text(progress)
                }
                if let currentPath = state.adoptCurrentPathText {
                    Text(currentPath)
                        .lineLimit(2)
                }
                if let warning = state.adoptWarningText {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var safetyText: some View {
        Text("Cancel opening only stops the UI opening flow. AreaMatrix does not move, rename, delete, or overwrite user files.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 640, alignment: .leading)
    }
}
