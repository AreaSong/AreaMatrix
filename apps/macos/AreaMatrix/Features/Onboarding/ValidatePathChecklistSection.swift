import SwiftUI

struct ValidatePathChecklist: View {
    let displayedPath: String
    let validation: RepoPathValidationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.title) { row in
                    ValidatePathCheckRowView(row: row)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
        }
    }

    private var rows: [ValidatePathCheckRow] {
        guard let validation else {
            return [
                .init(L10n.string("onboarding.validate.check.directory"), displayedPath, .checking),
                .init(L10n.string("onboarding.validate.check.readable"), waitingForCore, .checking),
                .init(L10n.string("onboarding.validate.check.writable"), waitingForCore, .checking),
                .init(
                    L10n.string("onboarding.validate.check.capacity"),
                    L10n.string("onboarding.validate.check.waitingCapacity"),
                    .checking
                ),
                .init(L10n.string("onboarding.validate.check.icloud"), waitingForCore, .checking),
                .init(
                    L10n.string("onboarding.validate.check.externalVolume"),
                    L10n.string("onboarding.validate.check.waitingVolume"),
                    .checking
                ),
                .init(L10n.string("onboarding.validate.check.existingRepo"), waitingForCore, .checking),
                .init(L10n.string("onboarding.validate.check.nonEmpty"), waitingForCore, .checking)
            ]
        }

        let isUsableDirectory = validation.exists && validation.isDirectory
        let hasNonEmptyDirectory = validation.issues.contains(.nonEmptyDirectory)

        return [
            .init(
                L10n.string("onboarding.validate.check.directory"),
                isUsableDirectory
                    ? L10n.string("onboarding.validate.check.candidateDirectory")
                    : L10n.string("onboarding.validate.check.chooseExistingFolder"),
                isUsableDirectory ? .passed : .failed
            ),
            .init(
                L10n.string("onboarding.validate.check.readable"),
                statusDetail(validation.isReadable),
                validation.isReadable ? .passed : .failed
            ),
            .init(
                L10n.string("onboarding.validate.check.writable"),
                statusDetail(validation.isWritable),
                validation.isWritable ? .passed : .failed
            ),
            .init(
                L10n.string("onboarding.validate.check.capacity"),
                capacityDetail(for: validation),
                capacityStatus(for: validation)
            ),
            .init(
                L10n.string("onboarding.validate.check.icloud"),
                validation.isICloudPath ? warningDetail : passedDetail,
                validation.isICloudPath ? .warning : .passed
            ),
            .init(
                L10n.string("onboarding.validate.check.externalVolume"),
                externalVolumeDetail(for: validation),
                externalVolumeStatus(for: validation)
            ),
            .init(
                L10n.string("onboarding.validate.check.existingRepo"),
                validation.isInitialized ? warningDetail : passedDetail,
                validation.isInitialized ? .warning : .passed
            ),
            .init(
                L10n.string("onboarding.validate.check.nonEmpty"),
                hasNonEmptyDirectory ? warningDetail : passedDetail,
                hasNonEmptyDirectory ? .warning : .passed
            )
        ]
    }

    private var waitingForCore: String {
        L10n.string("onboarding.validate.check.waitingCore")
    }

    private var passedDetail: String {
        L10n.string("onboarding.validate.check.passed")
    }

    private var warningDetail: String {
        L10n.string("onboarding.validate.check.warning")
    }

    private func statusDetail(_ passed: Bool) -> String {
        passed ? passedDetail : L10n.string("onboarding.validate.check.failed")
    }

    private func capacityDetail(for validation: RepoPathValidationSnapshot) -> String {
        guard let bytes = validation.availableCapacityBytes else {
            return L10n.string("onboarding.validate.check.missingResult")
        }

        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func capacityStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        if validation.hasInsufficientAvailableCapacity {
            return .failed
        }

        return validation.availableCapacityBytes == nil ? .failed : .passed
    }

    private func externalVolumeDetail(for validation: RepoPathValidationSnapshot) -> String {
        switch validation.isExternalVolume {
        case .some(true): warningDetail
        case .some(false): passedDetail
        case nil: L10n.string("onboarding.validate.check.missingResult")
        }
    }

    private func externalVolumeStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        switch validation.isExternalVolume {
        case .some(true): .warning
        case .some(false): .passed
        case nil: .failed
        }
    }
}

private struct ValidatePathCheckRow: Equatable {
    let title: String
    let detail: String
    let status: ValidatePathCheckStatus

    init(_ title: String, _ detail: String, _ status: ValidatePathCheckStatus) {
        self.title = title
        self.detail = detail
        self.status = status
    }
}

private struct ValidatePathCheckRowView: View {
    let row: ValidatePathCheckRow

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                Text(L10n.format("onboarding.validate.checkStatusDetail", row.status.text, row.detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: row.status.systemImage)
                .foregroundStyle(row.status.tint)
        }
    }
}
