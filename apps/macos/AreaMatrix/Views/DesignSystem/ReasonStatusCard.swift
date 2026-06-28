import SwiftUI

struct ReasonStatusCard<Title: View, Message: View, Actions: View>: View {
    let badge: String
    let badgeTint: Color
    let accessibilityIdentifier: String
    let badgeAccessibilityIdentifier: String
    let spacing: CGFloat
    private let title: Title
    private let message: Message
    private let actions: Actions

    init(
        badge: String,
        badgeTint: Color,
        accessibilityIdentifier: String,
        badgeAccessibilityIdentifier: String,
        spacing: CGFloat = 8,
        @ViewBuilder title: () -> Title,
        @ViewBuilder message: () -> Message,
        @ViewBuilder actions: () -> Actions
    ) {
        self.badge = badge
        self.badgeTint = badgeTint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.badgeAccessibilityIdentifier = badgeAccessibilityIdentifier
        self.spacing = spacing
        self.title = title()
        self.message = message()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeTint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier(badgeAccessibilityIdentifier)
                title
            }
            message
            actions
        }
        .padding(10)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
