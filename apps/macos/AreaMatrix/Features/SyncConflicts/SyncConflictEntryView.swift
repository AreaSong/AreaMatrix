import SwiftUI

enum SyncConflictEntryCopy {
    static var bannerTitle: String {
        L10n.string("Sync conflict needs review")
    }

    static var bannerMessage: String {
        L10n.string("AreaMatrix found files that may represent different versions. No version has been deleted.")
    }

    static var reviewAction: String {
        L10n.string("Review")
    }

    static var laterAction: String {
        L10n.string("Later")
    }

    static var listTitle: String {
        L10n.string("Needs Review")
    }

    static var loadingTitle: String {
        L10n.string("Checking conflicts...")
    }

    static var emptyTitle: String {
        L10n.string("No items need review.")
    }

    static var errorTitle: String {
        L10n.string("Could not load review items")
    }

    static var retryAction: String {
        L10n.string("Try again")
    }

    static var repairAction: String {
        L10n.string("Repair index first")
    }

    static var detailTitle: String {
        L10n.string("This file has a sync conflict")
    }
}

enum SyncConflictEntryAccessibilityID {
    static let panel = "sync-conflict-entry-sync-conflict-detect-sync-conflict-entry"
    static let banner = "sync-conflict-entry-sync-conflict-detect-conflict-banner"
    static let list = "sync-conflict-entry-sync-conflict-detect-needs-review-list"
    static let loading = "sync-conflict-entry-sync-conflict-detect-loading"
    static let empty = "sync-conflict-entry-sync-conflict-detect-empty"
    static let error = "sync-conflict-entry-sync-conflict-detect-error"
    static let retry = "sync-conflict-entry-sync-conflict-detect-retry"
    static let later = "sync-conflict-entry-sync-conflict-detect-later"
    static let review = "sync-conflict-entry-sync-conflict-detect-review"
    static let detailBanner = "sync-conflict-entry-sync-conflict-detect-detail-banner"

    static func row(_ conflictID: String) -> String {
        "sync-conflict-entry-sync-conflict-detect-row-\(safeID(conflictID))"
    }

    static func review(_ conflictID: String) -> String {
        "sync-conflict-entry-sync-conflict-detect-review-\(safeID(conflictID))"
    }

    private static func safeID(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? String(character)
                : "-"
        }.joined()
    }
}

struct SyncConflictEntryPanel: View {
    @ObservedObject var model: SyncConflictEntryModel
    let onReview: (SyncConflictReviewRoute) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(SyncConflictEntryCopy.listTitle, systemImage: "exclamationmark.triangle")
        }
        .task {
            await model.loadIfNeeded()
        }
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.panel)
    }
}

private extension SyncConflictEntryPanel {
    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .notLoaded, .loading:
            loadingContent
        case .empty:
            emptyContent
        case let .loaded(snapshot):
            loadedContent(snapshot)
        case let .failed(mapping):
            errorContent(mapping)
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(SyncConflictEntryCopy.loadingTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.loading)
    }

    private var emptyContent: some View {
        Text(SyncConflictEntryCopy.emptyTitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.empty)
    }

    private func loadedContent(_ snapshot: SyncConflictEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isBannerVisible {
                banner(snapshot)
            }
            metadataSummary(snapshot)
            VStack(spacing: 8) {
                ForEach(snapshot.conflicts) { conflict in
                    row(conflict)
                }
            }
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.list)
        }
    }

    private func banner(_ snapshot: SyncConflictEntrySnapshot) -> some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10,
            backgroundOpacity: 0.12
        ) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text(SyncConflictEntryCopy.bannerTitle)
                        .font(.callout.weight(.semibold))
                    Text(SyncConflictEntryCopy.bannerMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let conflict = snapshot.firstReviewableConflict {
                    Button(SyncConflictEntryCopy.reviewAction) {
                        onReview(model.reviewRoute(for: conflict))
                    }
                    .accessibilityIdentifier(SyncConflictEntryAccessibilityID.review)
                }
                Button(SyncConflictEntryCopy.laterAction) {
                    model.dismissBanner()
                }
                .accessibilityIdentifier(SyncConflictEntryAccessibilityID.later)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format(
            "%lld sync conflicts need review. %@.",
            snapshot.count,
            SyncConflictEntryCopy.reviewAction
        ))
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.banner)
    }

    private func metadataSummary(_ snapshot: SyncConflictEntrySnapshot) -> some View {
        HStack(spacing: 12) {
            Text(L10n.plural("syncConflict.count", count: snapshot.count))
            Text(L10n.format("syncConflict.latestDetected", snapshot.latestDetectedDisplay))
            Text(snapshot.typeSummary)
            Text(L10n.format("syncConflict.severity", snapshot.severitySummary))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func row(_ conflict: SyncConflictSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            badge(conflict)
            VStack(alignment: .leading, spacing: 3) {
                Text(conflict.fileDisplayName)
                    .font(.callout.weight(.semibold))
                Text(conflict.primaryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(L10n.format(
                    "syncConflict.entry.summary",
                    conflict.conflictType.displayName,
                    conflict.sourceDisplay,
                    conflict.detectedDisplay
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            reviewButton(conflict)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .contentShape(Rectangle())
        .onTapGesture {
            guard conflict.normalizedConflictID != nil else { return }
            onReview(model.reviewRoute(for: conflict))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(conflict))
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.row(conflict.conflictID))
    }

    private func badge(_ conflict: SyncConflictSnapshot) -> some View {
        Text(badgeTitle(conflict))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.16))
    }

    @ViewBuilder
    private func reviewButton(_ conflict: SyncConflictSnapshot) -> some View {
        if conflict.normalizedConflictID == nil {
            Text(SyncConflictEntryCopy.repairAction)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button(SyncConflictEntryCopy.reviewAction) {
                onReview(model.reviewRoute(for: conflict))
            }
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.review(conflict.conflictID))
        }
    }

    private func errorContent(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(SyncConflictEntryCopy.errorTitle, systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(mapping.userMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(SyncConflictEntryCopy.retryAction) {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.retry)
        }
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.error)
    }

    private func badgeTitle(_ conflict: SyncConflictSnapshot) -> String {
        switch conflict.conflictType {
        case .missingVersion:
            L10n.string("Missing version")
        case .unknown:
            L10n.string("Unknown source")
        case .sameNameDifferentContent, .concurrentModification, .metadataMismatch:
            L10n.string("Conflict")
        }
    }

    private func rowAccessibilityLabel(_ conflict: SyncConflictSnapshot) -> String {
        [
            conflict.fileDisplayName,
            conflict.conflictType.displayName,
            conflict.sourceDisplay,
            SyncConflictEntryCopy.reviewAction
        ].joined(separator: ". ")
    }
}

struct SyncConflictDetailBanner: View {
    let conflict: SyncConflictSnapshot?
    let onReview: (SyncConflictSnapshot) -> Void

    var body: some View {
        if let conflict {
            TintedStatusBanner(
                tint: .yellow,
                cornerRadius: 0,
                fillsWidth: false,
                contentPadding: 10,
                backgroundOpacity: 0.12
            ) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(SyncConflictEntryCopy.detailTitle)
                            .font(.callout.weight(.semibold))
                        Text(conflict.summaryDisplay)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(SyncConflictEntryCopy.reviewAction) {
                        onReview(conflict)
                    }
                    .disabled(conflict.normalizedConflictID == nil)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.format(
                "syncConflict.detail.accessibilityLabel",
                SyncConflictEntryCopy.detailTitle,
                conflict.fileDisplayName
            ))
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.detailBanner)
        }
    }
}
