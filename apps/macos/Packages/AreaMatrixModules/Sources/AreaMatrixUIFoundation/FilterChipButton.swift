import SwiftUI

/// A compact removable filter affordance shared by search and other filter-driven features.
public struct FilterChipButton: View {
    private let title: String
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(
        title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
    }
}
