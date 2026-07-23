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
        VStack(alignment: .leading, spacing: 10) {
            if isValidating {
                ProgressView(L10n.string("onboarding.validate.checkingPath"))
            }
            if let errorMapping {
                errorMappingNotice(errorMapping)
            } else if let errorMessage {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.pathUnavailable"),
                    image: "exclamationmark.triangle",
                    tint: .red,
                    lines: [localizer.resolve(errorMessage)]
                )
            }
            if validation?.isInitialized == true {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.repositoryFound"),
                    image: "externaldrive.connected.to.line.below",
                    tint: .green,
                    lines: existingRepoLines
                )
            }
            if ValidatePathNoticeRules.shouldShowAdoptExistingNotice(for: validation) {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.adoptTitle"),
                    image: "folder.badge.gearshape",
                    tint: .orange,
                    lines: [
                        L10n.string("onboarding.validate.adopt.createMetadata"),
                        L10n.string("onboarding.validate.adopt.scanFiles"),
                        L10n.string("onboarding.validate.adopt.noFileChanges"),
                        L10n.string("onboarding.validate.adopt.preserveStructure")
                    ]
                )
            }
            if validation?.isICloudPath == true {
                ValidatePathICloudNotice(
                    isAccepted: isICloudRiskAccepted,
                    onAcceptedChanged: onICloudRiskAcceptedChanged
                )
            }
            if validation?.isExternalVolume == true {
                ValidatePathNoticeCard(
                    title: L10n.string("onboarding.validate.externalVolumeTitle"),
                    image: "externaldrive",
                    tint: .orange,
                    lines: [
                        L10n.string("onboarding.validate.externalVolumeUnavailable"),
                        L10n.string("onboarding.validate.externalVolumeConfirm")
                    ]
                )
            }
            if let session = latestAdoptScanSession {
                scanSessionNotice(session)
            }
        }
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
            image: "arrow.clockwise.circle",
            tint: .orange,
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
            image: "exclamationmark.triangle",
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
        TintedOutlinedStatusBanner(tint: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("onboarding.validate.icloudTitle"), systemImage: "icloud")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text(L10n.string("onboarding.validate.icloudRisk"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle(
                    L10n.string("onboarding.validate.icloudRiskAcceptance"),
                    isOn: Binding(get: { isAccepted }, set: onAcceptedChanged)
                )
            }
        }
    }
}

private struct ValidatePathNoticeCard: View {
    let title: String
    let image: String
    let tint: Color
    let lines: [String]

    var body: some View {
        TintedOutlinedStatusBanner(tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: image)
                    .font(.headline)
                    .foregroundStyle(tint)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
