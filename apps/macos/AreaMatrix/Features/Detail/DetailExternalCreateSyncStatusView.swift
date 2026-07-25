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
                Button(L10n.string("Retry"), action: onRetry)
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
        L10n.format(
            "external-sync.detail.summary",
            event.relativePath,
            fileID,
            result.detectedCreates,
            result.detectedRenames,
            result.detectedDeletes,
            result.detectedModifies
        )
    }
}

enum TagSuggestionEditRowStatus: Equatable {
    case ready
    case duplicate(AppDisplayText)
    case invalid(AppDisplayText)
    case alreadyAdded(AppDisplayText)
    case blocked(AppDisplayText)
    case failed(AppDisplayText)
    case applied

    var label: String {
        switch self {
        case .ready: L10n.string("Ready")
        case .duplicate: L10n.string("Duplicate")
        case .invalid: L10n.string("Invalid")
        case .alreadyAdded: L10n.string("Already added")
        case .blocked: L10n.string("Blocked")
        case .failed: L10n.string("Failed")
        case .applied: L10n.string("Applied")
        }
    }

    var message: String? {
        switch self {
        case .ready, .applied:
            nil
        case let .duplicate(message), let .invalid(message), let .alreadyAdded(message), let .blocked(message),
             let .failed(message):
            L10n.resolve(message)
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
