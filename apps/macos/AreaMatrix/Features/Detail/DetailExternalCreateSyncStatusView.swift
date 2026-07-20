import SwiftUI

struct DetailExternalCreateSyncStatusView: View {
    let state: MainDetailExternalCreateSyncState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .syncing(_, event):
            Label(
                "Syncing external \(event.kind.displayName) file: \(event.relativePath)",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .synced(fileID, event, result):
            syncedStatus(event: event, fileID: fileID, result: result)
        case let .failed(_, event, mapping):
            failedStatus(event: event, mapping: mapping)
        }
    }

    private func syncedStatus(
        event: MainExternalCreatedFileEvent,
        fileID: Int64,
        result: SyncResultSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("External \(event.kind.displayName) file synced", systemImage: "checkmark.circle")
            Text(summary(event: event, fileID: fileID, result: result))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func failedStatus(
        event: MainExternalCreatedFileEvent,
        mapping: CoreErrorMappingSnapshot
    ) -> some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 8,
            backgroundOpacity: 0.12
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Label("External \(event.kind.displayName) sync failed", systemImage: "exclamationmark.triangle")
                Text(event.relativePath)
                    .foregroundStyle(.secondary)
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
                Button("Retry", action: onRetry)
                    .accessibilityIdentifier("external-sync-retry")
            }
            .font(.caption)
        }
    }

    private func summary(
        event: MainExternalCreatedFileEvent,
        fileID: Int64,
        result: SyncResultSnapshot
    ) -> String {
        """
        \(event.relativePath) · file #\(fileID) · created \(result.detectedCreates) · \
        renamed \(result.detectedRenames) · deleted \(result.detectedDeletes) · \
        modified \(result.detectedModifies)
        """
    }
}

enum TagSuggestionEditRowStatus: Equatable {
    case ready
    case duplicate(String)
    case invalid(String)
    case alreadyAdded(String)
    case blocked(String)
    case failed(String)
    case applied

    var label: String {
        switch self {
        case .ready: "Ready"
        case .duplicate: "Duplicate"
        case .invalid: "Invalid"
        case .alreadyAdded: "Already added"
        case .blocked: "Blocked"
        case .failed: "Failed"
        case .applied: "Applied"
        }
    }

    var message: String? {
        switch self {
        case .ready, .applied:
            nil
        case let .duplicate(message), let .invalid(message), let .alreadyAdded(message), let .blocked(message),
             let .failed(message):
            message
        }
    }

    var preventsApply: Bool {
        switch self {
        case .ready:
            false
        case .duplicate, .invalid, .alreadyAdded, .blocked, .failed, .applied:
            true
        }
    }
}

struct TagSuggestionEditDraft: Equatable, Identifiable {
    let suggestionID: String
    let originalSlug: String
    let originalDisplayName: String
    let reason: String
    var displayName: String
    var slug: String
    var slugWasEdited: Bool
    var status: TagSuggestionEditRowStatus

    var id: String {
        suggestionID
    }
}

struct TagSuggestionEditSession: Equatable {
    var selectedIDs: Set<String>
    var drafts: [TagSuggestionEditDraft]

    var attentionCount: Int {
        drafts.filter(\.status.preventsApply).count
    }

    var canApply: Bool {
        !drafts.isEmpty && drafts.allSatisfy { !$0.status.preventsApply }
    }

    var applyItems: [ApplyTagSuggestionItemSnapshot] {
        guard canApply else { return [] }
        return drafts.map(\.applyItem)
    }

    var retryFailedItems: [ApplyTagSuggestionItemSnapshot] {
        drafts.compactMap { draft in
            switch draft.status {
            case .failed:
                draft.applyItem
            case .ready, .duplicate, .invalid, .alreadyAdded, .blocked, .applied:
                nil
            }
        }
    }
}

private extension TagSuggestionEditDraft {
    var applyItem: ApplyTagSuggestionItemSnapshot {
        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ApplyTagSuggestionItemSnapshot(
            suggestionID: suggestionID,
            slug: slug,
            displayName: displayName.isEmpty ? slug : displayName
        )
    }
}
