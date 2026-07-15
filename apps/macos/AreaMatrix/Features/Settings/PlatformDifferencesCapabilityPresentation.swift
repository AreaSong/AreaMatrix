struct PlatformDifferencesCapabilityDisplayRow: Equatable, Identifiable {
    var name: String
    var support: PlatformCapabilitySupportSnapshot
    var detail: String
    var alternative: String?

    var id: String {
        name
    }
}

extension PlatformCapabilitiesSnapshot {
    var pageSpecRows: [PlatformDifferencesCapabilityDisplayRow] {
        [
            PlatformDifferencesCapabilityDisplayRow(
                name: "Repository access",
                support: securityBookmark,
                detail: "Uses platform repository permission or bookmark state from Core.",
                alternative: "Open repository settings if access needs to be renewed."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "File import",
                support: limitedFrom(
                    securityBookmark,
                    reason: "Import flows still rerun picker, permission, and duplicate preflight."
                ),
                detail: "Files and folders are imported only through their source flow.",
                alternative: "Return to the real import entry before choosing files."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "File watcher",
                support: watcher,
                detail: "Shows whether the platform can support repository change watching.",
                alternative: "Use manual rescan where watcher support is limited."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Cloud provider",
                support: cloudPlaceholder,
                detail: "Shows cloud placeholder or provider limitations without reporting sync progress.",
                alternative: "Use the platform cloud provider UI for exact sync state."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Trash / Recycle Bin",
                support: trash,
                detail: "Controls whether recoverable destructive actions may be enabled elsewhere.",
                alternative: "Keep dangerous actions disabled when this row is not available."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Share integration",
                support: shareExtension,
                detail: "Shows whether the platform exposes share or handoff entry points.",
                alternative: "Use file picker or drag and drop when share integration is unavailable."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Camera import",
                support: limitedFrom(
                    shareExtension,
                    reason: "Camera capture is validated by the camera import flow, not this page."
                ),
                detail: "This page only explains camera entry availability; capture preflight stays in import.",
                alternative: "Open the camera import flow for the final permission check."
            )
        ]
    }

    private func limitedFrom(
        _ support: PlatformCapabilitySupportSnapshot,
        reason: String
    ) -> PlatformCapabilitySupportSnapshot {
        guard support.status == .available else {
            return support.withAdditionalReason(reason)
        }

        return PlatformCapabilitySupportSnapshot(
            status: .limited,
            uiEnabled: false,
            requiresPermission: true,
            reason: reason
        )
    }
}

private extension PlatformCapabilitySupportSnapshot {
    func withAdditionalReason(_ additionalReason: String) -> PlatformCapabilitySupportSnapshot {
        let combinedReason: String = if let reason, !reason.isEmpty {
            "\(reason) \(additionalReason)"
        } else {
            additionalReason
        }

        return PlatformCapabilitySupportSnapshot(
            status: status,
            uiEnabled: uiEnabled,
            requiresPermission: requiresPermission,
            reason: combinedReason
        )
    }
}
