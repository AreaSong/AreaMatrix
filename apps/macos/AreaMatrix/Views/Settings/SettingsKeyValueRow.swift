import SwiftUI

struct SettingsKeyValueRow: View {
    enum ValueLayout {
        case truncated
        case wrapping
        case plain
    }

    let label: String
    let value: String
    var labelWidth: CGFloat = 140
    var spacing: CGFloat = 16
    var valueLayout: ValueLayout = .truncated

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .modifier(SettingsKeyValueTextLayout(valueLayout: valueLayout))
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
    }
}

private struct SettingsKeyValueTextLayout: ViewModifier {
    let valueLayout: SettingsKeyValueRow.ValueLayout

    func body(content: Content) -> some View {
        switch valueLayout {
        case .truncated:
            content
                .lineLimit(2)
                .truncationMode(.middle)
        case .wrapping:
            content
                .fixedSize(horizontal: false, vertical: true)
        case .plain:
            content
        }
    }
}

typealias ClassifierSettingsKeyValueRow = SettingsKeyValueRow
typealias RepositorySettingsKeyValueRow = SettingsKeyValueRow
