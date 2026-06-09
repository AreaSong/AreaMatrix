import SwiftUI

struct PlatformDifferencesCapabilityMatrixSection: View {
    let capabilities: PlatformDifferencesCapabilities

    var body: some View {
        Section("Capability matrix") {
            LabeledContent("Platform", value: capabilities.platform.rawValue)
            LabeledContent("App version", value: capabilities.appVersion)
            ForEach(capabilities.pageSpecRows) { row in
                PlatformDifferencesCapabilityRow(row: row)
            }
        }
    }
}

struct PlatformDifferencesReportSection: View {
    let report: PlatformDifferencesBindingContractReport

    var body: some View {
        Section("Contract status") {
            LabeledContent("Target", value: report.targetPlatform.rawValue)
            LabeledContent("Contract version", value: "\(report.bindingVersion)")
            LabeledContent("Core version", value: report.coreVersion)
            ForEach(report.supportedApis) { api in
                PlatformDifferencesStatusRow(
                    title: api.name,
                    detail: api.capability,
                    status: api.status,
                    reason: api.reason
                )
            }
            ForEach(report.typeMappings) { mapping in
                PlatformDifferencesStatusRow(
                    title: "\(mapping.rustType) -> \(mapping.targetType)",
                    detail: mapping.udlType,
                    status: mapping.status,
                    reason: mapping.reason
                )
            }
            if report.missingCapabilities.isEmpty {
                Label("No missing binding capabilities for this target.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                ForEach(report.missingCapabilities) { capability in
                    PlatformDifferencesStatusRow(
                        title: capability.label,
                        detail: capability.capability,
                        status: capability.status,
                        reason: capability.reason
                    )
                }
            }
        }
    }
}

extension PlatformDifferencesCapabilities {
    static func unknownSnapshot(
        platform: PlatformDifferencesPlatformId,
        appVersion: String,
        reason: String
    ) -> PlatformDifferencesCapabilities {
        let support = PlatformDifferencesCapabilitySupport(
            status: .unknown,
            uiEnabled: false,
            requiresPermission: false,
            reason: reason
        )
        return PlatformDifferencesCapabilities(
            platform: platform,
            appVersion: appVersion,
            watcher: support,
            trash: support,
            shareExtension: support,
            cloudPlaceholder: support,
            securityBookmark: support
        )
    }

    var pageSpecRows: [PlatformDifferencesCapabilityDisplayRow] {
        [
            PlatformDifferencesCapabilityDisplayRow(
                name: "Repository access",
                support: securityBookmark,
                detail: "Uses Files app authorization and security-scoped access state from Core.",
                alternative: "Open repository settings when repository access must be renewed."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "File import",
                support: limitedFrom(
                    securityBookmark,
                    reason: "Files import still reruns picker, placeholder, and replace preflight."
                ),
                detail: "Files app import stays in the import flow; this page only explains availability.",
                alternative: "Return to the Files import flow for the final permission check."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "File watcher",
                support: watcher,
                detail: "Shows whether the platform can keep repository changes up to date.",
                alternative: "Use open-time scan when background watching is limited."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Cloud provider",
                support: cloudPlaceholder,
                detail: "Shows iCloud placeholder limitations without reporting exact sync progress.",
                alternative: "Use Files or iCloud settings for exact sync state."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Trash / Recycle Bin",
                support: trash,
                detail: "Controls whether recoverable destructive actions may be enabled elsewhere.",
                alternative: "Keep Replace and delete flows disabled when this row is not available."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Share integration",
                support: shareExtension,
                detail: "Shows whether Share Sheet handoff is supported.",
                alternative: "Use Files import when share integration is unavailable."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Camera import",
                support: limitedFrom(
                    shareExtension,
                    reason: "Camera capture is validated by the camera import flow, not this page."
                ),
                detail: "Camera availability is explained here; capture permission stays in camera import.",
                alternative: "Open camera import for the final permission check."
            )
        ]
    }

    private func limitedFrom(
        _ support: PlatformDifferencesCapabilitySupport,
        reason: String
    ) -> PlatformDifferencesCapabilitySupport {
        guard support.status == .available else {
            return support.withAdditionalReason(reason)
        }

        return PlatformDifferencesCapabilitySupport(
            status: .limited,
            uiEnabled: false,
            requiresPermission: true,
            reason: reason
        )
    }
}

private struct PlatformDifferencesCapabilityRow: View {
    let row: PlatformDifferencesCapabilityDisplayRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.name)
                Spacer()
                Text(row.support.status.rawValue)
                    .font(.caption.weight(.semibold))
            }
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("UI enabled: \(row.support.uiEnabled ? "Yes" : "No")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if row.support.requiresPermission {
                Text("Requires platform permission before use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reason = row.support.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let alternative = row.alternative, !alternative.isEmpty {
                Text(alternative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlatformDifferencesStatusRow: View {
    let title: String
    let detail: String
    let status: PlatformDifferencesBindingSupportStatus
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension PlatformDifferencesCapabilitySupport {
    func withAdditionalReason(_ additionalReason: String) -> PlatformDifferencesCapabilitySupport {
        let combinedReason: String
        if let reason, !reason.isEmpty {
            combinedReason = "\(reason) \(additionalReason)"
        } else {
            combinedReason = additionalReason
        }

        return PlatformDifferencesCapabilitySupport(
            status: status,
            uiEnabled: uiEnabled,
            requiresPermission: requiresPermission,
            reason: combinedReason
        )
    }
}
