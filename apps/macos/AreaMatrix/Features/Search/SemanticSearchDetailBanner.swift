import SwiftUI

struct SemanticSearchDetailBanner: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let detail: SemanticSearchDetailPresentation

    var body: some View {
        TintedStatusBanner(
            tint: .blue,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.resolve(detail.title))
                    .font(.callout.weight(.semibold))
                Text("Relevance \(detail.relevance)  \(detail.routeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup(L10n.string("Why this matched")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.matchedReason)
                        Text(detail.whyThisMatched.resolve(using: localizer))
                        if detail.alsoMatchedNormalSearch {
                            Text(L10n.string("Also matched normal search"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
        }
        .accessibilityIdentifier("semantic-search-semantic-detail-explanation")
    }
}
