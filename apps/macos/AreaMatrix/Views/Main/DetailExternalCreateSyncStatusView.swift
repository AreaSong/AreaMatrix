import SwiftUI

struct DetailExternalCreateSyncStatusView: View {
    let state: MainDetailExternalCreateSyncState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .syncing(event):
            Label(
                "Syncing external \(event.kind.displayName) file: \(event.relativePath)",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .synced(event, fileID, result):
            syncedStatus(event: event, fileID: fileID, result: result)
        case let .failed(event, mapping):
            failedStatus(event: event, mapping: mapping)
        }
    }

    private func syncedStatus(
        event: MainExternalCreatedFileEvent,
        fileID: Int64?,
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
        VStack(alignment: .leading, spacing: 4) {
            Label("External \(event.kind.displayName) sync failed", systemImage: "exclamationmark.triangle")
            Text(event.relativePath)
                .foregroundStyle(.secondary)
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(8)
        .background(Color.yellow.opacity(0.12))
    }

    private func summary(
        event: MainExternalCreatedFileEvent,
        fileID: Int64?,
        result: SyncResultSnapshot
    ) -> String {
        let fileText = fileID.map { "file #\($0)" } ?? "file not selected"
        return """
        \(event.relativePath) · \(fileText) · created \(result.detectedCreates) · \
        renamed \(result.detectedRenames) · deleted \(result.detectedDeletes)
        """
    }
}

enum TagSuggestionEditRowStatus: Equatable {
    case ready
    case duplicate(String)
    case invalid(String)
    case alreadyAdded(String)
    case blocked(String)
    case applied

    var label: String {
        switch self {
        case .ready: "Ready"
        case .duplicate: "Duplicate"
        case .invalid: "Invalid"
        case .alreadyAdded: "Already added"
        case .blocked: "Blocked"
        case .applied: "Applied"
        }
    }

    var message: String? {
        switch self {
        case .ready, .applied:
            nil
        case let .duplicate(message), let .invalid(message), let .alreadyAdded(message), let .blocked(message):
            message
        }
    }

    var preventsApply: Bool {
        switch self {
        case .ready:
            false
        case .duplicate, .invalid, .alreadyAdded, .blocked, .applied:
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

    var id: String { suggestionID }
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
        return drafts.map {
            ApplyTagSuggestionItemSnapshot(
                suggestionID: $0.suggestionID,
                slug: $0.slug,
                displayName: $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
