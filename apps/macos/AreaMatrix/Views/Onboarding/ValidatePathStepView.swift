import SwiftUI

struct ValidatePathStepView: View {
    let pathText: String
    let validation: RepoPathValidationSnapshot?
    let existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    let latestScanSession: ScanSessionSnapshot?
    let errorMessage: String?
    let errorMapping: CoreErrorMappingSnapshot?
    let isValidating: Bool
    let isICloudRiskAccepted: Bool
    let canContinue: Bool
    let primaryActionTitle: String
    let showsCancel: Bool
    let onBack: () -> Void
    let onCancel: () -> Void
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onICloudRiskAcceptedChanged: (Bool) -> Void
    let onContinue: () -> Void

    private var displayedPath: String {
        validation?.repoPath ?? pathText
    }

    var body: some View {
        VStack(alignment: .center, spacing: 28) {
            ValidatePathHeader()

            VStack(spacing: 24) {
                ValidatePathSummary(displayedPath: displayedPath)
                ValidatePathChecklist(displayedPath: displayedPath, validation: validation)
                ValidatePathNotices(
                    displayedPath: displayedPath,
                    validation: validation,
                    existingRepositoryMetadata: existingRepositoryMetadata,
                    latestScanSession: latestScanSession,
                    errorMessage: errorMessage,
                    errorMapping: errorMapping,
                    isValidating: isValidating,
                    isICloudRiskAccepted: isICloudRiskAccepted,
                    onICloudRiskAcceptedChanged: onICloudRiskAcceptedChanged
                )
            }
            .frame(maxWidth: 440)

            ValidatePathFooter(
                isInitializedRepository: validation?.isInitialized == true,
                isValidating: isValidating,
                canContinue: canContinue,
                primaryActionTitle: primaryActionTitle,
                showsCancel: showsCancel,
                onBack: onBack,
                onCancel: onCancel,
                onChangePath: onChangePath,
                onRetry: onRetry,
                onContinue: onContinue
            )
        }
        .areaMatrixOnboardingPanel()
    }
}

private struct ValidatePathHeader: View {
    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.blue)
                .padding(.bottom, 8)

            Text("校验资料库路径")
                .font(.system(size: 32, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)

            Text("AreaMatrix 会先检查路径状态，再进入初始化或打开流程。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ValidatePathSummary: View {
    let displayedPath: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(displayedPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        }
    }
}
