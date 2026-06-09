import SwiftUI

struct RepositoryInitConfirmContent: Equatable {
    var title = "Create AreaMatrix Repository"
    var folderPath: String
    var pathType: String
    var writableText: String
    var safetyText = "AreaMatrix will create a .areamatrix folder here."
    var noOverwriteText = "No existing files will be moved, deleted, renamed, or overwritten."
    var checklistItems: [InitSafetyChecklistItem]
    var riskText: String?
    var disabledReason: String?
    var canCreate: Bool

    init(candidate: MobileRepositoryCandidate, error: MobileRepositoryConnectionError? = nil) {
        let validation = candidate.validation
        folderPath = validation.repoPath
        pathType = Self.pathTypeText(for: validation.platformPathKind)
        writableText = validation.isWritable ? "Yes" : "No"
        riskText = Self.riskText(for: validation)
        canCreate = Self.canCreateRepository(from: validation)
        disabledReason = Self.disabledReason(for: validation, error: error)
        checklistItems = [
            Self.folderItem(for: validation),
            Self.writePermissionItem(for: validation),
            Self.diskSpaceItem()
        ]
    }

    private static func pathTypeText(for kind: MobileRepositoryPlatformPathKind) -> String {
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

    private static func riskText(for validation: MobileRepositoryValidation) -> String? {
        if validation.isICloudPath || validation.platformPathKind == .iCloudDrive {
            return "iCloud sync is managed by the system. AreaMatrix will not download placeholders here."
        }
        if validation.isThirdPartyCloudPath || validation.platformPathKind == .oneDrive {
            return "Cloud sync behavior is controlled by the selected provider."
        }
        if validation.platformPathKind == .networkShare {
            return "Network folders can become unavailable; retry if metadata creation fails."
        }
        return nil
    }

    private static func folderItem(for validation: MobileRepositoryValidation) -> InitSafetyChecklistItem {
        if validation.exists {
            return InitSafetyChecklistItem(
                title: "Folder is empty",
                detail: validation.isEmpty ? "Ready for metadata creation." : "Choose an empty folder for this step.",
                status: validation.isEmpty ? .passed : .blocked
            )
        }
        return InitSafetyChecklistItem(
            title: "Folder can be created",
            detail: validation.recommendedMode == .createEmpty
                ? "Core accepted this path for empty repository creation."
                : "Choose a folder AreaMatrix can create.",
            status: validation.recommendedMode == .createEmpty ? .passed : .blocked
        )
    }

    private static func writePermissionItem(
        for validation: MobileRepositoryValidation
    ) -> InitSafetyChecklistItem {
        InitSafetyChecklistItem(
            title: "Write permission available",
            detail: validation.isWritable ? "AreaMatrix can write metadata." : "Reconnect or choose another folder.",
            status: validation.isWritable ? .passed : .blocked
        )
    }

    private static func diskSpaceItem() -> InitSafetyChecklistItem {
        InitSafetyChecklistItem(
            title: "Enough disk space",
            detail: "Core verifies metadata writes during creation.",
            status: .pending
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
        if validation.recommendedMode != .createEmpty {
            return "This folder is not eligible for empty repository creation."
        }
        if validation.isInsideAreaMatrix {
            return "Choose the repository folder, not its .areamatrix metadata folder."
        }
        if validation.exists, !validation.isDirectory {
            return "Choose a folder, not a file."
        }
        if validation.exists, !validation.isReadable {
            return "AreaMatrix cannot read this folder."
        }
        if !validation.isWritable {
            return "AreaMatrix cannot write metadata in this folder."
        }
        if validation.exists, !validation.isEmpty {
            return "Choose an empty folder for this confirmation."
        }
        return nil
    }

    private static func canCreateRepository(from validation: MobileRepositoryValidation) -> Bool {
        validation.recommendedMode == .createEmpty
            && validation.isWritable
            && !validation.isInitialized
            && !validation.isInsideAreaMatrix
            && (!validation.exists || (validation.isDirectory && validation.isReadable && validation.isEmpty))
    }
}

struct InitSafetyChecklistItem: Equatable, Identifiable {
    enum Status: Equatable {
        case passed
        case pending
        case blocked
    }

    var id: String {
        title
    }

    var title: String
    var detail: String
    var status: Status
}

struct RepositoryInitConfirmView: View {
    let candidate: MobileRepositoryCandidate
    let isChecking: Bool
    let isCreating: Bool
    let error: MobileRepositoryConnectionError?
    let onRefresh: (MobileRepositoryCandidate) -> Void
    let onCreate: (MobileRepositoryCandidate) -> Void
    let onChooseAnotherFolder: () -> Void
    let onCancel: () -> Void

    @State private var refreshedPaths: Set<String> = []

    private var content: RepositoryInitConfirmContent {
        RepositoryInitConfirmContent(candidate: candidate, error: error)
    }

    var body: some View {
        List {
            RepositoryPathSummary(content: content)
            InitSafetyChecklist(items: content.checklistItems, riskText: content.riskText)
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

    @ViewBuilder
    private var failureSection: some View {
        if let error {
            Section {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try Again") {
                    onCreate(candidate)
                }
                .disabled(isChecking || isCreating)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                onCreate(candidate)
            } label: {
                HStack {
                    Text(isCreating ? "Creating metadata..." : "Create Repository")
                    if isCreating {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isChecking || isCreating || !content.canCreate)
            .accessibilityHint(content.disabledReason ?? "Creates AreaMatrix metadata in this folder.")

            Button("Choose Another Folder", action: onChooseAnotherFolder)
                .disabled(isChecking || isCreating)

            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isCreating)
        } footer: {
            if isChecking, !isCreating {
                Text("Checking folder...")
            } else if let disabledReason = content.disabledReason, !content.canCreate {
                Text(disabledReason)
            }
        }
    }
}

private struct RepositoryPathSummary: View {
    let content: RepositoryInitConfirmContent

    var body: some View {
        Section {
            Label(content.safetyText, systemImage: "checkmark.shield")
            Text(content.noOverwriteText)
                .foregroundStyle(.secondary)
            LabeledContent("Folder", value: content.folderPath)
                .textSelection(.enabled)
            LabeledContent("Type", value: content.pathType)
            LabeledContent("Writable", value: content.writableText)
        }
    }
}

private struct InitSafetyChecklist: View {
    let items: [InitSafetyChecklistItem]
    let riskText: String?

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
            if let riskText {
                Label(riskText, systemImage: "cloud")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func systemImage(for status: InitSafetyChecklistItem.Status) -> String {
        switch status {
        case .passed:
            "checkmark.circle.fill"
        case .pending:
            "clock"
        case .blocked:
            "xmark.circle.fill"
        }
    }

    private func color(for status: InitSafetyChecklistItem.Status) -> Color {
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

struct RepositoryRoutePlaceholderView: View {
    let content: ConnectRepositoryRouteDestinationContent

    var body: some View {
        List {
            Section {
                Label(content.primaryText, systemImage: content.systemImage)
                if let pathText = content.pathText {
                    Text(pathText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .connectRepositoryListStyle()
        .navigationTitle(content.title)
    }
}
