import AreaMatrixCoreBridgeContract
import AreaMatrixUIFoundation
import SwiftUI

struct ValidatePathStepView: View {
    let pathText: String
    let validation: RepoPathValidationSnapshot?
    let existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    let latestScanSession: ScanSessionSnapshot?
    let errorMessage: LocalizedMessage?
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
        VStack(spacing: 0) {
            // ================== 顶部：极简信息极 ==================
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    AreaMatrixLucideIcon(name: .hardDrive, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(AreaMatrixTheme.Colors.teal)
                    Text("DIAGNOSTICS")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(AreaMatrixTheme.Colors.teal)
                        .tracking(4)
                }

                AreaMatrixPathBox(path: displayedPath)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 48)

            // ================== 中枢：巨型深空雷达与卫星阵列 ==================
            Spacer(minLength: 40)

            ValidatePathSatelliteRadar(
                displayedPath: displayedPath,
                validation: validation,
                isValidating: isValidating,
                errorMessage: errorMessage
            )

            Spacer(minLength: 40)

            // ================== 底部：极简状态与控制 ==================
            VStack(spacing: 32) {
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
                .frame(maxWidth: 600)

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
            .padding(.bottom, 48)
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
    }
}
