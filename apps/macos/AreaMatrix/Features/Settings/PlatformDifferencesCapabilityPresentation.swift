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
                name: L10n.string("Repository access"),
                support: securityBookmark,
                detail: L10n.string("Uses platform repository permission or bookmark state from Core."),
                alternative: L10n.string("Open repository settings if access needs to be renewed.")
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: L10n.string("File import"),
                support: limitedFrom(
                    securityBookmark,
                    reason: L10n.string("Import flows still rerun picker, permission, and duplicate preflight.")
                ),
                detail: L10n.string("Files and folders are imported only through their source flow."),
                alternative: L10n.string("Return to the real import entry before choosing files.")
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: L10n.string("File watcher"),
                support: watcher,
                detail: L10n.string("Shows whether the platform can support repository change watching."),
                alternative: L10n.string("Use manual rescan where watcher support is limited.")
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: L10n.string("Cloud provider"),
                support: cloudPlaceholder,
                detail: L10n.string(
                    "Shows cloud placeholder or provider limitations without reporting sync progress."
                ),
                alternative: L10n.string("Use the platform cloud provider UI for exact sync state.")
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: L10n.string("Trash / Recycle Bin"),
                support: trash,
                detail: L10n.string("Controls whether recoverable destructive actions may be enabled elsewhere."),
                alternative: L10n.string("Keep dangerous actions disabled when this row is not available.")
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: L10n.string("Share integration"),
                support: shareExtension,
                detail: L10n.string("Shows whether the platform exposes share or handoff entry points."),
                alternative: L10n.string("Use file picker or drag and drop when share integration is unavailable.")
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: L10n.string("Camera import"),
                support: limitedFrom(
                    shareExtension,
                    reason: L10n.string("Camera capture is validated by the camera import flow, not this page.")
                ),
                detail: L10n.string(
                    "This page only explains camera entry availability; capture preflight stays in import."
                ),
                alternative: L10n.string("Open the camera import flow for the final permission check.")
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
