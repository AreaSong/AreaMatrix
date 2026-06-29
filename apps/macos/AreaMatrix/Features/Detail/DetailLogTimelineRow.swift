import SwiftUI

struct ChangeTimelineRow: View {
    let entry: ChangeLogEntrySnapshot
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(entry.detailJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.actionDisplayName)
                    .font(.callout.weight(.semibold))
                Text(entry.occurredAtDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.detailSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
