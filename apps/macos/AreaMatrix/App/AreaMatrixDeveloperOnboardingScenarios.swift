import SwiftUI

#if DEBUG
@MainActor
struct DeveloperOnboardingScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .onboardingConfirm:
            ConfirmInitStepView(
                draft: DeveloperOnboardingScenarioFixture.draft,
                onBack: {},
                onChangePath: {},
                onCreateEmpty: {},
                onAdoptExisting: {},
                onCancelSetup: {}
            )
        case .onboardingDatabaseRepair:
            DeveloperDatabaseRepairScenario()
        case .onboardingDone:
            InitDoneStepView(
                result: DeveloperOnboardingScenarioFixture.result,
                errorMapping: nil,
                onOpenRepository: {},
                onOpenInFinder: {}
            )
        case .onboardingFailed:
            InitFailedStepView(
                repoPath: AreaMatrixPreviewFixtures.repositoryPath,
                mapping: DeveloperOnboardingScenarioFixture.databaseFailure,
                diagnostics: .collected(DeveloperOnboardingScenarioFixture.diagnostics),
                canRetry: true,
                onChangePath: {},
                onRetry: {},
                onCollectDiagnostics: {},
                onQuit: {}
            )
        case .onboardingInitializing:
            InitializingStepView(
                draft: DeveloperOnboardingScenarioFixture.draft,
                scanSession: DeveloperOnboardingScenarioFixture.runningScan,
                recoveryReport: DeveloperOnboardingScenarioFixture.recoveryReport,
                progressWarning: nil,
                isCancellationRequested: false,
                onCancel: {}
            )
        case .onboardingRecovery:
            DeveloperStartupRecoveryScenario()
        case .onboardingValidatePath:
            ValidatePathStepView(
                pathText: AreaMatrixPreviewFixtures.repositoryPath,
                validation: DeveloperOnboardingScenarioFixture.validation,
                existingRepositoryMetadata: nil,
                latestScanSession: nil,
                errorMessage: nil,
                errorMapping: nil,
                isValidating: false,
                isICloudRiskAccepted: false,
                canContinue: true,
                primaryActionTitle: L10n.string("onboarding.validate.continue"),
                showsCancel: false,
                onBack: {},
                onCancel: {},
                onChangePath: {},
                onRetry: {},
                onICloudRiskAcceptedChanged: { _ in },
                onContinue: {}
            )
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperDatabaseRepairScenario: View {
    private let core = DeveloperOnboardingCoreFixture()

    var body: some View {
        DBRepairConfirmView(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            scanSession: DeveloperOnboardingScenarioFixture.completedScan,
            mapping: DeveloperOnboardingScenarioFixture.databaseFailure,
            lastOpenedAt: 1_778_738_400,
            metadataRepairer: core,
            repositoryReindexer: core,
            startupRecoverer: core,
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: DeveloperOnboardingDiagnosticsCollector(),
            errorMapper: CoreErrorSnapshotMapper(),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
    }
}

private struct DeveloperStartupRecoveryScenario: View {
    var body: some View {
        VStack {
            Spacer()
            StartupRecoveryErrorRecoveryView(
                state: .failed(DeveloperOnboardingScenarioFixture.recoveryFailure),
                onRetry: {}
            )
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
