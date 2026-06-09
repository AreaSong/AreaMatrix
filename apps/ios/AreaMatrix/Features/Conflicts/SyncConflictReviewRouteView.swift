import SwiftUI

struct SyncConflictReviewRouteView: View {
    let route: SyncConflictEntryReviewRoute

    var body: some View {
        List {
            Section {
                Label("Review sync conflict", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(route.primaryPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Conflict ID: \(route.conflictID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                Text(
                    "AreaMatrix opened the review route without resolving, replacing, "
                        + "moving, or deleting any version."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .mobileLibraryListStyle()
        .navigationTitle("Review sync conflict")
        .accessibilityIdentifier("S4-X-01-C4-15-ios-review-route")
    }
}
