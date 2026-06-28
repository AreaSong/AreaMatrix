import SwiftUI

struct AISettingsInlineBanner<Actions: View>: View {
    let error: AISettingsError
    let tint: Color
    private let actions: Actions

    init(error: AISettingsError, tint: Color, @ViewBuilder actions: () -> Actions) {
        self.error = error
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        TintedStatusBanner(tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(error.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(error.recovery)
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
