import SwiftUI

struct RepositoryAdoptConfirmContent: Equatable {
    var title = "Use Existing Folder"
    var folderPath: String
    var estimatedItemsText: String
    var writableText: String
    var locationTypeText: String
    var metadataText = "AreaMatrix will create a .areamatrix folder for metadata and scan this folder."
    var noOverwriteText = "AreaMatrix will not move, delete, rename, or overwrite existing files."
    var rollbackText = "Removing .areamatrix later must not remove your original files."
    var checklistItems: [AdoptSafetyChecklistItem]
    var requiresHighRiskAcknowledgement: Bool
    var disabledReason: String?
    var canAdopt: Bool

    init(candidate: MobileRepositoryCandidate, error: MobileRepositoryConnectionError? = nil) {
        let validation = candidate.validation
        folderPath = validation.repoPath
        estimatedItemsText = validation.isEmpty ? "0" : "Non-empty folder"
        writableText = validation.isWritable ? "Yes" : "No"
        locationTypeText = Self.locationTypeText(for: validation.platformPathKind)
        requiresHighRiskAcknowledgement = Self.requiresHighRiskAcknowledgement(validation)
        canAdopt = Self.canAdoptRepository(from: validation)
        disabledReason = Self.disabledReason(for: validation, error: error)
        checklistItems = [
            Self.nonEmptyFolderItem(for: validation),
            Self.writePermissionItem(for: validation),
            Self.metadataItem(for: validation),
            Self.cloudRiskItem(for: validation)
        ]
    }

    private static func locationTypeText(for kind: MobileRepositoryPlatformPathKind) -> String {
        switch kind {
        case .local:
            "Local folder"
        case .iCloudDrive:
            "iCloud Drive"
        case .oneDrive:
            "OneDrive"
        case .networkShare:
            "Network mount"
        case .unknown:
            "Unknown"
        }
    }

    private static func requiresHighRiskAcknowledgement(_ validation: MobileRepositoryValidation) -> Bool {
        validation.isICloudPath
            || validation.isThirdPartyCloudPath
            || validation.platformPathKind == .networkShare
            || validation.platformPathKind == .unknown
    }

    private static func nonEmptyFolderItem(
        for validation: MobileRepositoryValidation
    ) -> AdoptSafetyChecklistItem {
        AdoptSafetyChecklistItem(
            title: "Folder contains existing files",
            detail: validation.isEmpty
                ? "Use empty repository creation instead."
                : "AreaMatrix will index existing files in place.",
            status: validation.isEmpty ? .blocked : .passed
        )
    }

    private static func writePermissionItem(
        for validation: MobileRepositoryValidation
    ) -> AdoptSafetyChecklistItem {
        AdoptSafetyChecklistItem(
            title: "Write permission available",
            detail: validation.isWritable ? "AreaMatrix can write metadata." : "Reconnect or choose another folder.",
            status: validation.isWritable ? .passed : .blocked
        )
    }

    private static func metadataItem(for validation: MobileRepositoryValidation) -> AdoptSafetyChecklistItem {
        AdoptSafetyChecklistItem(
            title: "Metadata folder can be added",
            detail: validation.isInitialized
                ? "This folder already contains AreaMatrix metadata."
                : "Only .areamatrix metadata will be added.",
            status: validation.isInitialized ? .blocked : .pending
        )
    }

    private static func cloudRiskItem(for validation: MobileRepositoryValidation) -> AdoptSafetyChecklistItem {
        let isRisky = requiresHighRiskAcknowledgement(validation)
        return AdoptSafetyChecklistItem(
            title: "Sync and mount risk reviewed",
            detail: isRisky
                ? "This location may sync or report changes differently."
                : "No extra sync or mount warning was reported.",
            status: isRisky ? .pending : .passed
        )
    }

    private static func disabledReason(
        for validation: MobileRepositoryValidation,
        error: MobileRepositoryConnectionError?
    ) -> String? {
        if let error {
            return error.message
        }
        if validation.isInitialized {
            return "This folder is already an AreaMatrix repository."
        }
        if validation.recommendedMode != .adoptExisting {
            return "This folder is not eligible for existing folder adoption."
        }
        if validation.isInsideAreaMatrix {
            return "Choose the repository folder, not its .areamatrix metadata folder."
        }
        if !validation.exists {
            return "Choose an existing folder."
        }
        if !validation.isDirectory {
            return "Choose a folder, not a file."
        }
        if !validation.isReadable {
            return "AreaMatrix cannot read this folder."
        }
        if !validation.isWritable {
            return "AreaMatrix cannot write metadata in this folder."
        }
        if validation.isEmpty {
            return "Use empty repository creation for this folder."
        }
        if validation.hasUnfinishedScanSession {
            return "This folder has an unfinished scan session; recover it before adopting again."
        }
        return nil
    }

    private static func canAdoptRepository(from validation: MobileRepositoryValidation) -> Bool {
        validation.recommendedMode == .adoptExisting
            && validation.exists
            && validation.isDirectory
            && validation.isReadable
            && validation.isWritable
            && !validation.isEmpty
            && !validation.isInitialized
            && !validation.isInsideAreaMatrix
            && !validation.hasUnfinishedScanSession
    }
}

struct AdoptSafetyChecklistItem: Equatable, Identifiable {
    enum Status: Equatable {
        case passed
        case pending
        case blocked
    }

    var id: String { title }
    var title: String
    var detail: String
    var status: Status
}

struct RepositoryAdoptConfirmView: View {
    let candidate: MobileRepositoryCandidate
    let isChecking: Bool
    let isCreating: Bool
    let error: MobileRepositoryConnectionError?
    let onRefresh: (MobileRepositoryCandidate) -> Void
    let onAdopt: (MobileRepositoryCandidate) -> Void
    let onChooseAnotherFolder: () -> Void
    let onCancel: () -> Void

    @State private var metadataAcknowledged = false
    @State private var highRiskAcknowledged = false
    @State private var refreshedPaths: Set<String> = []

    private var content: RepositoryAdoptConfirmContent {
        RepositoryAdoptConfirmContent(candidate: candidate, error: error)
    }

    private var canUseFolder: Bool {
        content.canAdopt
            && metadataAcknowledged
            && (!content.requiresHighRiskAcknowledgement || highRiskAcknowledged)
    }

    var body: some View {
        List {
            AdoptFolderSummary(content: content)
            AdoptSafetyChecklist(items: content.checklistItems)
            acknowledgementSection
            failureSection
            actionSection
        }
        .connectRepositoryListStyle()
        .navigationTitle(content.title)
        .task(id: candidate.validation.repoPath) {
            guard refreshedPaths.insert(candidate.validation.repoPath).inserted else { return }
            onRefresh(candidate)
        }
    }

    private var acknowledgementSection: some View {
        Section("Confirmation") {
            Toggle("I understand AreaMatrix will add metadata to this folder.", isOn: $metadataAcknowledged)
                .disabled(isCreating)
            if content.requiresHighRiskAcknowledgement {
                Toggle(
                    "I understand this location may sync or report changes differently.",
                    isOn: $highRiskAcknowledged
                )
                .disabled(isCreating)
            }
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if let error {
            Section {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try Again") {
                    onAdopt(candidate)
                }
                .disabled(isChecking || isCreating || !canUseFolder)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                onAdopt(candidate)
            } label: {
                HStack {
                    Text(isCreating ? "Preparing repository..." : "Use This Folder")
                    if isCreating {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isChecking || isCreating || !canUseFolder)
            .accessibilityHint(content.disabledReason ?? "Creates metadata and scans this folder.")

            Button("Choose Another Folder", action: onChooseAnotherFolder)
                .disabled(isChecking || isCreating)

            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isCreating)
        } footer: {
            if isChecking, !isCreating {
                Text("Checking folder...")
            } else if let disabledReason = content.disabledReason, !content.canAdopt {
                Text(disabledReason)
            }
        }
    }
}

private struct AdoptFolderSummary: View {
    let content: RepositoryAdoptConfirmContent

    var body: some View {
        Section {
            Label(content.noOverwriteText, systemImage: "checkmark.shield")
            Text(content.metadataText)
                .foregroundStyle(.secondary)
            Text(content.rollbackText)
                .foregroundStyle(.secondary)
            LabeledContent("Folder", value: content.folderPath)
                .textSelection(.enabled)
            LabeledContent("Estimated items", value: content.estimatedItemsText)
            LabeledContent("Writable", value: content.writableText)
            LabeledContent("Location type", value: content.locationTypeText)
        }
    }
}

private struct AdoptSafetyChecklist: View {
    let items: [AdoptSafetyChecklistItem]

    var body: some View {
        Section("Checks") {
            ForEach(items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: systemImage(for: item.status))
                        .foregroundStyle(color(for: item.status))
                }
            }
        }
    }

    private func systemImage(for status: AdoptSafetyChecklistItem.Status) -> String {
        switch status {
        case .passed:
            "checkmark.circle.fill"
        case .pending:
            "clock"
        case .blocked:
            "xmark.circle.fill"
        }
    }

    private func color(for status: AdoptSafetyChecklistItem.Status) -> Color {
        switch status {
        case .passed:
            .green
        case .pending:
            .secondary
        case .blocked:
            .red
        }
    }
}
