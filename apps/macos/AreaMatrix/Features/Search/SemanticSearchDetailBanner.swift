import SwiftUI

struct SemanticSearchDetailBanner: View {
    let detail: SemanticSearchDetailPresentation

    var body: some View {
        TintedStatusBanner(
            tint: .blue,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.title)
                    .font(.callout.weight(.semibold))
                Text("Relevance \(detail.relevance)  \(detail.routeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Why this matched") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.matchedReason)
                        Text(detail.whyThisMatched)
                        if detail.alsoMatchedNormalSearch {
                            Text("Also matched normal search")
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
