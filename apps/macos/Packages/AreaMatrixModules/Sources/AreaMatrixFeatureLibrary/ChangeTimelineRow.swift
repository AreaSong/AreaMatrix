import SwiftUI

public struct ChangeTimelineRow: View {
    private let action: String
    private let occurredAt: String
    private let summary: String
    private let detail: String
    @State private var isExpanded = false

    public init(action: String, occurredAt: String, summary: String, detail: String) {
        self.action = action
        self.occurredAt = occurredAt
        self.summary = summary
        self.detail = detail
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(action)
                    .font(.callout.weight(.semibold))
                Text(occurredAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
