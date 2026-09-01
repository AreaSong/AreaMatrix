import AreaMatrixCoreBridgeContract
import AreaMatrixUIFoundation
import SwiftUI

enum ValidatePathNoticeRules {
    static func shouldShowAdoptExistingNotice(for validation: RepoPathValidationSnapshot?) -> Bool {
        guard let validation, !validation.isInitialized else {
            return false
        }

        return validation.recommendedMode == .adoptExisting ||
            validation.issues.contains(.nonEmptyDirectory)
    }
}

struct ValidatePathNotices: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let displayedPath: String
    let validation: RepoPathValidationSnapshot?
    let existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    let latestScanSession: ScanSessionSnapshot?
    let errorMessage: LocalizedMessage?
    let errorMapping: CoreErrorMappingSnapshot?
    let isValidating: Bool
    let isICloudRiskAccepted: Bool
    let onICloudRiskAcceptedChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            if isValidating {
                ProgressView(L10n.string("onboarding.validate.checkingPath"))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let errorMapping {
                errorMappingNotice(errorMapping)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let errorMessage {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.pathUnavailable"),
                    icon: .alertTriangle,
                    tint: AreaMatrixTheme.Colors.coral,
                    lines: [localizer.resolve(errorMessage)]
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if validation?.isInitialized == true {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.repositoryFound"),
                    icon: .hardDrive,
                    tint: AreaMatrixTheme.Colors.emerald,
                    lines: existingRepoLines
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if ValidatePathNoticeRules.shouldShowAdoptExistingNotice(for: validation) {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.adoptTitle"),
                    icon: .folderCog,
                    tint: AreaMatrixTheme.Colors.gold,
                    lines: [
                        L10n.string("onboarding.validate.adopt.createMetadata"),
                        L10n.string("onboarding.validate.adopt.scanFiles"),
                        L10n.string("onboarding.validate.adopt.noFileChanges"),
                        L10n.string("onboarding.validate.adopt.preserveStructure")
                    ]
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if validation?.isICloudPath == true {
                ValidatePathICloudNotice(
                    isAccepted: isICloudRiskAccepted,
                    onAcceptedChanged: onICloudRiskAcceptedChanged
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if validation?.isExternalVolume == true {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.externalVolumeTitle"),
                    icon: .hardDrive,
                    tint: AreaMatrixTheme.Colors.gold,
                    lines: [
                        L10n.string("onboarding.validate.externalVolumeUnavailable"),
                        L10n.string("onboarding.validate.externalVolumeConfirm")
                    ]
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let session = latestAdoptScanSession {
                scanSessionNotice(session)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isValidating)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: validation)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: errorMapping)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: errorMessage)
    }

    private var latestAdoptScanSession: ScanSessionSnapshot? {
        latestScanSession?.kind == .adopt ? latestScanSession : nil
    }

    private var existingRepoLines: [String] {
        [
            L10n.string("onboarding.validate.existingRepo.databaseFound"),
            L10n.string("onboarding.validate.existingRepo.openOnly"),
            schemaVersionLine,
            lastOpenedLine,
            L10n.format("onboarding.validate.repoPath", displayedPath)
        ]
    }

    private var schemaVersionLine: String {
        guard let version = existingRepositoryMetadata?.schemaVersion else {
            return L10n.string("onboarding.validate.schemaReading")
        }

        return L10n.format("onboarding.validate.schemaVersion", version)
    }

    private var lastOpenedLine: String {
        guard let lastOpenedAt = existingRepositoryMetadata?.lastOpenedAt else {
            return L10n.string("onboarding.validate.lastOpenedNotRecorded")
        }

        let date = Date(timeIntervalSince1970: TimeInterval(lastOpenedAt))
        return L10n.format(
            "onboarding.validate.lastOpened",
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func scanSessionNotice(_ session: ScanSessionSnapshot) -> some View {
        ValidatePathNoticeCard(
            title: L10n.string("onboarding.validate.unfinishedScanTitle"),
            icon: .refreshCcw,
            tint: AreaMatrixTheme.Colors.gold,
            lines: [
                L10n.format("onboarding.validate.scanStatus", session.status.displayName),
                L10n.format("onboarding.validate.scanCounts", session.inserted, session.updated, session.skipped),
                L10n.format(
                    "onboarding.validate.lastPath",
                    session.lastPath ?? L10n.string("onboarding.validate.notRecorded")
                )
            ]
        )
    }

    private func errorMappingNotice(_ mapping: CoreErrorMappingSnapshot) -> some View {
        ValidatePathNoticeCard(
            title: L10n.string("onboarding.validate.pathUnavailable"),
            icon: .alertTriangle,
            tint: mapping.severity.tint,
            lines: [
                mapping.userMessage,
                L10n.format("onboarding.validate.suggestedAction", mapping.suggestedAction),
                L10n.format(
                    "onboarding.validate.severityRecoverability",
                    mapping.severity.displayName,
                    mapping.recoverability.displayName
                )
            ]
        )
    }
}

private struct ValidatePathICloudNotice: View {
    let isAccepted: Bool
    let onAcceptedChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                AreaMatrixLucideIcon(name: .cloud, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.blue)
                Text(L10n.string("onboarding.validate.icloudTitle"))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .center, spacing: 8) {
                Text(L10n.string("onboarding.validate.icloudRisk"))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Toggle(
                    L10n.string("onboarding.validate.icloudRiskAcceptance"),
                    isOn: Binding(get: { isAccepted }, set: onAcceptedChanged)
                )
                .font(.system(size: 12, weight: .bold))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .padding(.top, 8)
    }
}

private struct ValidatePathNoticeCard: View {
    let title: String
    let icon: AreaMatrixLucideIcon.IconName
    let tint: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                AreaMatrixLucideIcon(name: icon, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
            }

            if !lines.isEmpty {
                VStack(alignment: .center, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}
