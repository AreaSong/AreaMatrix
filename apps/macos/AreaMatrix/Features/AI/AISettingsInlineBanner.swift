import AreaMatrixUIFoundation
import SwiftUI

struct AISettingsInlineBanner<Actions: View>: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let error: AISettingsError
    let tint: Color
    private let actions: Actions

    init(error: AISettingsError, tint: Color, @ViewBuilder actions: () -> Actions) {
        self.error = error
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        AreaMatrixInlineErrorBanner(
            message: localizer.resolve(error.message),
            detail: error.detail,
            recovery: localizer.resolve(error.recovery),
            tint: tint
        ) {
            actions
        }
    }
}
