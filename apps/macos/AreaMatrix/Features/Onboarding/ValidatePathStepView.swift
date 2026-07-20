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
            AreaMatrixStepHeader(
                systemImage: "checklist",
                tint: .blue,
                title: "校验资料库路径",
                subtitle: "AreaMatrix 会先检查路径状态，再进入初始化或打开流程。"
            )

            VStack(spacing: 24) {
                AreaMatrixPathBox(path: displayedPath)
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
