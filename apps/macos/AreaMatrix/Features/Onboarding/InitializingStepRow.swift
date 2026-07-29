import SwiftUI

struct InitializingStepRow {
    let title: String
    let iconName: AreaMatrixLucideIcon.IconName
    let tint: Color

    static func pending(_ title: String) -> InitializingStepRow {
        InitializingStepRow(title: title, iconName: .clock, tint: .secondary)
    }

    static func running(_ title: String, when condition: Bool) -> InitializingStepRow {
        condition ? InitializingStepRow(title: title, iconName: .refreshCcw, tint: AreaMatrixTheme.Colors.teal)
            : pending(title)
    }

    static func completed(_ title: String, when condition: Bool) -> InitializingStepRow {
        condition ? InitializingStepRow(title: title, iconName: .checkCircle, tint: AreaMatrixTheme.Colors.teal) :
            pending(title)
    }
}
