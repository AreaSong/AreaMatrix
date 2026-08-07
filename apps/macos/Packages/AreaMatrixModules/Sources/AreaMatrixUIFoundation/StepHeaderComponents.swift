import SwiftUI

/// Default icon used by centered onboarding and recovery step headers.
public struct AreaMatrixStepHeaderIcon: View {
    public let systemImage: String
    public let tint: Color

    public init(systemImage: String, tint: Color) {
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 48, weight: .light))
            .foregroundStyle(tint)
    }
}

/// Reusable centered header for a step-like page.
public struct AreaMatrixStepHeader<Icon: View>: View {
    public let title: String
    public let subtitle: String
    private let icon: Icon

    public init(
        title: String,
        subtitle: String,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon()
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 14) {
            icon
                .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
}

public extension AreaMatrixStepHeader where Icon == AreaMatrixStepHeaderIcon {
    init(systemImage: String, tint: Color, title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            AreaMatrixStepHeaderIcon(systemImage: systemImage, tint: tint)
        }
    }
}
