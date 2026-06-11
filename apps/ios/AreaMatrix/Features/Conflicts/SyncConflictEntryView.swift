import SwiftUI

enum SyncConflictEntryCopy {
    static let title = "Sync conflict needs review"
    static let message = "AreaMatrix found files that may represent different versions. No version has been deleted."
    static let review = "Review"
    static let later = "Later"
    static let checking = "Checking conflicts..."
    static let empty = "No items need review."
    static let error = "Could not load review items"
    static let retry = "Try again"
    static let repair = "Repair index first"
    static let detailTitle = "This file has a sync conflict"
}

enum SyncConflictEntryAccessibilityID {
    static let mobileHome = "S4-X-03-C4-15-ios-mobile-home"
    static let detailBanner = "S4-X-03-C4-15-ios-detail-banner"
    static let retry = "S4-X-03-C4-15-ios-retry"
    static let later = "S4-X-03-C4-15-ios-later"
    static let review = "S4-X-03-C4-15-ios-review"
}

enum SyncConflictEntryState: Equatable {
    case notLoaded
    case loading
    case empty
    case loaded([SyncConflictEntryConflict])
    case failed(SyncConflictEntryError)

    var conflicts: [SyncConflictEntryConflict] {
        guard case let .loaded(conflicts) = self else { return [] }
        return conflicts
    }
}

@MainActor
final class SyncConflictEntryViewModel: ObservableObject {
    @Published private(set) var state: SyncConflictEntryState = .notLoaded
    @Published private(set) var isBannerDismissed = false

    private let repoPath: String
    private let bridge: any SyncConflictEntryCoreBridge
    private var generation = 0

    init(repoPath: String, bridge: any SyncConflictEntryCoreBridge) {
        self.repoPath = repoPath
        self.bridge = bridge
    }

    var reviewableConflicts: [SyncConflictEntryConflict] {
        state.conflicts
    }

    var isBannerVisible: Bool {
        !isBannerDismissed && !reviewableConflicts.isEmpty
    }

    var firstReviewableConflict: SyncConflictEntryConflict? {
        reviewableConflicts.first { $0.normalizedConflictID != nil }
    }

    func loadIfNeeded() async {
        guard case .notLoaded = state else { return }
        await reload(resetDismissal: false)
    }

    func refresh() async {
        await reload(resetDismissal: true)
    }

    func dismissBanner() {
        isBannerDismissed = true
    }

    func reviewRoute(for conflict: SyncConflictEntryConflict) -> SyncConflictEntryReviewRoute? {
        guard let conflictID = conflict.normalizedConflictID else { return nil }
        return SyncConflictEntryReviewRoute(
            repoPath: repoPath,
            conflictID: conflictID,
            primaryPath: conflict.primaryPath
        )
    }

    func detailConflict(fileID: Int64, path: String) -> SyncConflictEntryConflict? {
        reviewableConflicts.first { $0.matches(fileID: fileID, path: path) }
    }

    private func reload(resetDismissal: Bool) async {
        generation += 1
        let currentGeneration = generation
        if resetDismissal {
            isBannerDismissed = false
        }
        state = .loading
        do {
            let conflicts = try await bridge.detectSyncConflicts(repoPath: repoPath)
            guard currentGeneration == generation else { return }
            let reviewable = conflicts
                .filter { $0.status == .needsReview }
                .sorted(by: sortConflicts)
            state = reviewable.isEmpty ? .empty : .loaded(reviewable)
        } catch {
            guard currentGeneration == generation else { return }
            state = .failed(SyncConflictEntryError.map(error))
        }
    }

    private func sortConflicts(
        _ lhs: SyncConflictEntryConflict,
        _ rhs: SyncConflictEntryConflict
    ) -> Bool {
        if lhs.severity.sortRank != rhs.severity.sortRank {
            return lhs.severity.sortRank > rhs.severity.sortRank
        }
        return (lhs.detectedAt ?? 0) > (rhs.detectedAt ?? 0)
    }
}

struct SyncConflictEntryMobileHomeSection: View {
    @ObservedObject var model: SyncConflictEntryViewModel
    let onReview: (SyncConflictEntryReviewRoute) -> Void

    var body: some View {
        Section("Needs Review") {
            content
        }
        .accessibilityIdentifier(SyncConflictEntryAccessibilityID.mobileHome)
        .task {
            await model.loadIfNeeded()
        }
    }
}

private extension SyncConflictEntryMobileHomeSection {
    @ViewBuilder
    var content: some View {
        switch model.state {
        case .notLoaded, .loading:
            ProgressView(SyncConflictEntryCopy.checking)
        case .empty:
            Label(SyncConflictEntryCopy.empty, systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case let .failed(error):
            VStack(alignment: .leading, spacing: 6) {
                Label(SyncConflictEntryCopy.error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(SyncConflictEntryCopy.retry) {
                    Task { await model.refresh() }
                }
                .accessibilityIdentifier(SyncConflictEntryAccessibilityID.retry)
            }
        case let .loaded(conflicts):
            loaded(conflicts)
        }
    }

    func loaded(_ conflicts: [SyncConflictEntryConflict]) -> some View {
        Group {
            if model.isBannerVisible {
                banner(conflicts)
            }
            ForEach(conflicts) { conflict in
                conflictRow(conflict)
            }
        }
    }

    func banner(_ conflicts: [SyncConflictEntryConflict]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(SyncConflictEntryCopy.title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(SyncConflictEntryCopy.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if let conflict = model.firstReviewableConflict,
                   let route = model.reviewRoute(for: conflict) {
                    Button(SyncConflictEntryCopy.review) {
                        onReview(route)
                    }
                    .accessibilityIdentifier(SyncConflictEntryAccessibilityID.review)
                }
                Button(SyncConflictEntryCopy.later) {
                    model.dismissBanner()
                }
                .accessibilityIdentifier(SyncConflictEntryAccessibilityID.later)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conflicts.count) sync conflicts need review")
    }

    func conflictRow(_ conflict: SyncConflictEntryConflict) -> some View {
        Button {
            if let route = model.reviewRoute(for: conflict) {
                onReview(route)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(conflict.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(conflict.primaryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(conflict.conflictType.displayName) · \(conflict.sourceText) · \(conflict.detectedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(conflict.normalizedConflictID == nil)
        .accessibilityHint(conflict.normalizedConflictID == nil ? SyncConflictEntryCopy.repair : "")
    }
}

struct SyncConflictEntryDetailBanner: View {
    let conflict: SyncConflictEntryConflict?
    let onReview: (SyncConflictEntryReviewRoute) -> Void
    let route: SyncConflictEntryReviewRoute?

    var body: some View {
        if let conflict {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(SyncConflictEntryCopy.detailTitle, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(conflict.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(SyncConflictEntryCopy.review) {
                        if let route {
                            onReview(route)
                        }
                    }
                    .disabled(route == nil)
                }
            }
            .accessibilityIdentifier(SyncConflictEntryAccessibilityID.detailBanner)
        }
    }
}
