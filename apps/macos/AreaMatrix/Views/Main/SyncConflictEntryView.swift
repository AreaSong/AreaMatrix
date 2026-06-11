import SwiftUI

enum SyncConflictEntryCopy {
    static let bannerTitle = "Sync conflict needs review"
    static let bannerMessage =
        "AreaMatrix found files that may represent different versions. No version has been deleted."
    static let reviewAction = "Review"
    static let laterAction = "Later"
    static let listTitle = "Needs Review"
    static let loadingTitle = "Checking conflicts..."
    static let emptyTitle = "No items need review."
    static let errorTitle = "Could not load review items"
    static let retryAction = "Try again"
    static let repairAction = "Repair index first"
    static let detailTitle = "This file has a sync conflict"
}

enum SyncConflictEntryAccessibilityID {
    static let panel = "S4-X-03-C4-15-sync-conflict-entry"
    static let banner = "S4-X-03-C4-15-conflict-banner"
    static let list = "S4-X-03-C4-15-needs-review-list"
    static let loading = "S4-X-03-C4-15-loading"
    static let empty = "S4-X-03-C4-15-empty"
    static let error = "S4-X-03-C4-15-error"
    static let retry = "S4-X-03-C4-15-retry"
    static let later = "S4-X-03-C4-15-later"
    static let review = "S4-X-03-C4-15-review"
    static let detailBanner = "S4-X-03-C4-15-detail-banner"

    static func row(_ conflictID: String) -> String {
        "S4-X-03-C4-15-row-\(safeID(conflictID))"
    }

    static func review(_ conflictID: String) -> String {
        "S4-X-03-C4-15-review-\(safeID(conflictID))"
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
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.count) sync conflicts need review. \(SyncConflictEntryCopy.reviewAction).")
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.banner)
    }

    private func metadataSummary(_ snapshot: SyncConflictEntrySnapshot) -> some View {
        HStack(spacing: 12) {
            Text("\(snapshot.count) conflicts")
            Text("Latest \(snapshot.latestDetectedDisplay)")
            Text(snapshot.typeSummary)
            Text("Severity \(snapshot.severitySummary)")
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
                Text("\(conflict.conflictType.displayName) - \(conflict.sourceDisplay) - \(conflict.detectedDisplay)")
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
            "Missing version"
        case .unknown:
            "Unknown source"
        case .sameNameDifferentContent, .concurrentModification, .metadataMismatch:
            "Conflict"
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
            .padding(10)
            .background(Color.yellow.opacity(0.12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(SyncConflictEntryCopy.detailTitle). \(conflict.fileDisplayName). Review.")
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.detailBanner)
        }
    }
}
