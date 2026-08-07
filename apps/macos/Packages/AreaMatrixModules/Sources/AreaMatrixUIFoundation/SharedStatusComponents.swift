import SwiftUI

/// Compact, neutral status primitives shared by feature pages.
///
/// These components intentionally accept caller-owned content and colors. They
/// do not own localization or feature state, which keeps them safe to reuse
/// from any feature module without coupling the foundation package to the App
/// target.
public struct NeutralCapsuleChip<Content: View>: View {
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var backgroundOpacity: Double
    private let content: Content

    public init(
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 3,
        backgroundOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    public var body: some View {
        content
            .font(.caption)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Color.secondary.opacity(backgroundOpacity), in: Capsule())
    }
}

public struct NeutralSummaryPanel<Content: View>: View {
    public var contentPadding: CGFloat
    public var cornerRadius: CGFloat
    public var backgroundOpacity: Double
    private let content: Content

    public init(
        contentPadding: CGFloat = 10,
        cornerRadius: CGFloat = 8,
        backgroundOpacity: Double = 0.10,
        @ViewBuilder content: () -> Content
    ) {
        self.contentPadding = contentPadding
        self.cornerRadius = cornerRadius
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    public var body: some View {
        content
            .padding(contentPadding)
            .background(Color.secondary.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

public struct ReasonStatusCard<Title: View, Message: View, Actions: View>: View {
    public let badge: String
    public let badgeTint: Color
    public let accessibilityIdentifier: String
    public let badgeAccessibilityIdentifier: String
    public let spacing: CGFloat
    private let title: Title
    private let message: Message
    private let actions: Actions

    public init(
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

    public var body: some View {
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

public struct TintedCapsuleBadge: View {
    public let title: String
    public let tint: Color
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var backgroundOpacity: Double

    public init(
        title: String,
        tint: Color,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 3,
        backgroundOpacity: Double = 0.12
    ) {
        self.title = title
        self.tint = tint
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundOpacity = backgroundOpacity
    }

    public var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(backgroundOpacity), in: Capsule())
            .foregroundStyle(tint)
    }
}

public struct TintedStatusBanner<Content: View>: View {
    public let tint: Color
    public let cornerRadius: CGFloat
    public let fillsWidth: Bool
    public let contentPadding: CGFloat
    public let backgroundOpacity: Double
    private let content: Content

    public init(
        tint: Color,
        cornerRadius: CGFloat = 8,
        fillsWidth: Bool = true,
        contentPadding: CGFloat = 12,
        backgroundOpacity: Double = 0.08,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.fillsWidth = fillsWidth
        self.contentPadding = contentPadding
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    public var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .background(tint.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

public struct TintedOutlinedStatusBanner<Content: View>: View {
    public let tint: Color
    public let cornerRadius: CGFloat
    private let content: Content

    public init(
        tint: Color,
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(tint.opacity(0.15), lineWidth: 1))
    }
}
