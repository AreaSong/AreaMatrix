import SwiftUI

enum SyncConflictReviewCopy {
    static let title = "Review sync conflict"
    static let subtitle = "Compare detected versions before choosing a resolution."
    static let loadingTitle = "Loading conflict details..."
    static let emptyTitle = "Conflict no longer exists."
    static let errorTitle = "Unable to load sync conflict"
    static let backAction = "Back to Needs Review"
    static let refreshAction = "Refresh"
    static let closeAction = "Close"
}

enum SyncConflictReviewAccessibilityID {
    static let page = "S4-X-01-C4-15-sync-conflict-review"
    static let loading = "S4-X-01-C4-15-loading"
    static let empty = "S4-X-01-C4-15-empty"
    static let error = "S4-X-01-C4-15-error"
    static let retry = "S4-X-01-C4-15-retry"
    static let refresh = "S4-X-01-C4-15-refresh"
    static let back = "S4-X-01-C4-15-back"
    static let close = "S4-X-01-C4-15-close"
    static let summary = "S4-X-01-C4-15-summary"
    static let versions = "S4-X-01-C4-15-versions"

    static func versionCard(fileID: String) -> String {
        "S4-X-01-C4-15-version-\(safeID(fileID))"
    }

    private static func safeID(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? String(character)
                : "-"
        }.joined()
    }
}

struct SyncConflictReviewView: View {
    @StateObject private var model: SyncConflictReviewModel
    let onBackToNeedsReview: () -> Void
    let onClose: () -> Void

    init(
        model: SyncConflictReviewModel,
        onBackToNeedsReview: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.onBackToNeedsReview = onBackToNeedsReview
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            if case .notLoaded = model.state {
                await model.load()
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.page)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(SyncConflictReviewCopy.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(SyncConflictReviewCopy.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(SyncConflictReviewCopy.loadingTitle)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .notLoaded, .loading:
            loadingContent
        case let .loaded(conflict):
            conflictContent(conflict)
        case .empty:
            emptyContent
        case let .failed(mapping):
            errorContent(mapping)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(SyncConflictReviewCopy.loadingTitle)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.loading)
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(SyncConflictReviewCopy.emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text("Refresh the conflict entry list and choose another item.")
        } actions: {
            Button(SyncConflictReviewCopy.backAction, action: onBackToNeedsReview)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.back)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.empty)
    }

    private func errorContent(_ mapping: CoreErrorMappingSnapshot) -> some View {
        ContentUnavailableView {
            Label(SyncConflictReviewCopy.errorTitle, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 4) {
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                Text("Severity: \(mapping.severity.rawValue); Recoverability: \(mapping.recoverability.rawValue)")
                if !mapping.rawContext.isEmpty {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } actions: {
            Button("Retry") {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(SyncConflictReviewAccessibilityID.retry)
            Button(SyncConflictReviewCopy.backAction, action: onBackToNeedsReview)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.back)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.error)
    }

    private func conflictContent(_ conflict: SyncConflictSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection(conflict)
                versionSection(conflict.affectedFiles)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summarySection(_ conflict: SyncConflictSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(conflict.summaryDisplay)
                    .font(.headline)
                metadataGrid(rows: [
                    ("Conflict type", conflict.conflictType.displayName),
                    ("File", conflict.primaryPath),
                    ("Status", conflict.status.displayName),
                    ("Severity", conflict.severity.displayName),
                    ("Versions", "\(conflict.versionCount)"),
                    ("Source", conflict.sourceDisplay),
                    ("Detected", conflict.detectedDisplay),
                    ("Conflict ID", conflict.conflictID)
                ])
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.summary)
    }

    private func versionSection(_ files: [SyncConflictAffectedFileSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Versions")
                .font(.headline)
            ForEach(files) { file in
                versionCard(file)
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.versions)
    }

    private func versionCard(_ file: SyncConflictAffectedFileSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(file.role.displayName)
                    .font(.headline)
                metadataGrid(rows: [
                    ("Path", file.path),
                    ("Size", file.sizeDisplay),
                    ("Modified", file.modifiedDisplay),
                    ("Hash", file.hashDisplay),
                    ("Source platform", file.sourceDisplay),
                    ("File ID", file.fileID.map(String.init) ?? "Unknown")
                ])
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.versionCard(fileID: file.id))
    }

    private func metadataGrid(rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(SyncConflictReviewCopy.backAction, action: onBackToNeedsReview)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.back)
            Spacer()
            Button(SyncConflictReviewCopy.refreshAction) {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(SyncConflictReviewAccessibilityID.refresh)
            Button(SyncConflictReviewCopy.closeAction, action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.close)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
