import SwiftUI

/// Shared presentation for a localized error with detail, recovery copy and feature actions.
public struct AreaMatrixInlineErrorBanner<Actions: View>: View {
    private let message: String
    private let detail: String
    private let recovery: String
    private let tint: Color
    private let actions: Actions

    public init(
        message: String,
        detail: String,
        recovery: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.message = message
        self.detail = detail
        self.recovery = recovery
        self.tint = tint
        self.actions = actions()
    }

    public var body: some View {
        TintedStatusBanner(tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    actions
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
