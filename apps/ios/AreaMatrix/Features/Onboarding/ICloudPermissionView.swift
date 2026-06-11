import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct ICloudPermissionContent: Equatable {
    enum RecoveryAction: String, Equatable {
        case tryAgain = "Try Again"
        case reconnectFolder = "Reconnect Folder"
        case chooseAnotherFolder = "Choose Another Folder"
        case openSettings = "Open Settings"
    }

    var title: String
    var systemImage: String
    var message: String
    var status: String
    var repositoryText: String?
    var primaryAction: RecoveryAction
    var secondaryActions: [RecoveryAction]
    var safetyText: String

    init(
        error: MobileRepositoryConnectionError,
        cloudState: MobileCloudStorageState?
    ) {
        let source = ICloudPermissionContentSource(error: error, cloudState: cloudState)
        title = source.title
        systemImage = source.systemImage
        message = source.message
        status = source.status
        repositoryText = source.repositoryText
        primaryAction = source.primaryAction
        secondaryActions = source.secondaryActions
        safetyText = "AreaMatrix will not delete, move, or modify your repository files because of this permission issue."
    }
}

private struct ICloudPermissionContentSource {
    let error: MobileRepositoryConnectionError
    let cloudState: MobileCloudStorageState?

    var title: String {
        if isPlaceholder {
            return "File is still in iCloud"
        }
        if isAccessExpired || isPermissionDenied {
            return "Repository access expired"
        }
        return "iCloud Drive is not available"
    }

    var systemImage: String {
        isAccessExpired || isPermissionDenied ? "folder.badge.questionmark" : "icloud.slash"
    }

    var message: String {
        if isPlaceholder {
            return "This file exists in iCloud but is not downloaded on this device yet."
        }
        if isPermissionDenied {
            return "AreaMatrix needs access to the folder that contains your repository."
        }
        if isAccessExpired {
            return "iOS requires you to reconnect this folder before AreaMatrix can read it again."
        }
        if let summary = cloudState?.statusSummary, !summary.isEmpty {
            return summary
        }
        return error.message
    }

    var status: String {
        if isPlaceholder {
            return "Waiting for iCloud download"
        }
        if isPermissionDenied {
            return "Permission denied"
        }
        if isAccessExpired {
            return "Access expired"
        }
        return "Could not check iCloud status"
    }

    var repositoryText: String? {
        if let path = cloudState?.repoPath, !path.isEmpty {
            return path
        }
        switch error {
        case let .permissionDenied(path), let .accessExpired(path), let .iCloudPlaceholder(path):
            return path
        case .invalidPath, .selectedFile, .invalidRepository, .unavailable:
            return nil
        }
    }

    var primaryAction: ICloudPermissionContent.RecoveryAction {
        if isAccessExpired || isPermissionDenied {
            return .reconnectFolder
        }
        return .tryAgain
    }

    var secondaryActions: [ICloudPermissionContent.RecoveryAction] {
        var actions: [ICloudPermissionContent.RecoveryAction] = [.chooseAnotherFolder]
        if shouldShowSettings {
            actions.append(.openSettings)
        }
        return actions
    }

    private var isPlaceholder: Bool {
        if cloudState?.placeholderState == .placeholder { return true }
        if case .iCloudPlaceholder = error { return true }
        return false
    }

    private var isAccessExpired: Bool {
        if cloudState?.requiresReconnect == true { return true }
        if cloudState?.recommendedAction == .reconnectFolder { return true }
        if cloudState?.permissionState == .accessExpired { return true }
        if case .accessExpired = error { return true }
        return false
    }

    private var isPermissionDenied: Bool {
        if cloudState?.permissionState == .permissionDenied { return true }
        if case .permissionDenied = error { return true }
        return false
    }

    private var shouldShowSettings: Bool {
        if cloudState?.providerKind == .iCloudDrive || cloudState?.providerKind == .unknown {
            return true
        }
        if case .unavailable = error {
            return true
        }
        return isPermissionDenied || isAccessExpired
    }
}

struct ICloudPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedSettings = false

    let content: ICloudPermissionContent
    let isChecking: Bool
    let onTryAgain: () -> Void
    let onReconnectFolder: () -> Void
    let onChooseAnotherFolder: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(content.title)
                            .font(.title3.weight(.semibold))
                        Text(content.message)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: content.systemImage)
                        .foregroundStyle(.orange)
                }
                Text(content.safetyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                if let repositoryText = content.repositoryText {
                    statusRow(title: "Repository", value: repositoryText)
                }
                statusRow(title: "Status", value: isChecking ? "Checking..." : content.status)
            }

            Section {
                Button(action: performPrimaryAction) {
                    actionLabel(content.primaryAction.rawValue, isProminent: true)
                }
                .disabled(isChecking)

                ForEach(content.secondaryActions, id: \.self) { action in
                    Button {
                        perform(action)
                    } label: {
                        actionLabel(action.rawValue, isProminent: false)
                    }
                    .disabled(isChecking)
                }
            }
        }
        .icloudPermissionListStyle()
        .navigationTitle(content.title)
        .toolbar {
            Button("Back") {
                dismiss()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard openedSettings, phase == .active else { return }
            openedSettings = false
            onTryAgain()
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func actionLabel(_ title: String, isProminent: Bool) -> some View {
        HStack {
            Text(title)
                .font(isProminent ? .headline : .body)
            if isChecking && isProminent {
                ProgressView()
            }
        }
    }

    private func performPrimaryAction() {
        perform(content.primaryAction)
    }

    private func perform(_ action: ICloudPermissionContent.RecoveryAction) {
        switch action {
        case .tryAgain:
            onTryAgain()
        case .reconnectFolder:
            onReconnectFolder()
        case .chooseAnotherFolder:
            onChooseAnotherFolder()
        case .openSettings:
            openedSettings = true
            onOpenSettings()
        }
    }
}

private extension View {
    @ViewBuilder
    func icloudPermissionListStyle() -> some View {
        #if os(iOS)
            listStyle(.insetGrouped)
        #else
            listStyle(.inset)
        #endif
    }
}

enum ICloudPermissionSystemSettings {
    @MainActor
    static func open() {
        #if os(iOS)
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        #endif
    }
}
