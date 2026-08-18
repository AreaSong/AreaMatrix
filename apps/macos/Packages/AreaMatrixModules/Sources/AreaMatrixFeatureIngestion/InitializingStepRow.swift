import AreaMatrixUIFoundation
import SwiftUI

public struct InitializingStepRow {
    public let title: String
    public let iconName: AreaMatrixLucideIcon.IconName
    public let tint: Color

    public init(title: String, iconName: AreaMatrixLucideIcon.IconName, tint: Color) {
        self.title = title
        self.iconName = iconName
        self.tint = tint
    }

    public static func pending(_ title: String) -> Self {
        Self(title: title, iconName: .clock, tint: .secondary)
    }

    public static func running(_ title: String, when condition: Bool) -> Self {
        condition ? Self(title: title, iconName: .refreshCcw, tint: AreaMatrixTheme.Colors.teal) : pending(title)
    }

    public static func completed(_ title: String, when condition: Bool) -> Self {
        condition ? Self(title: title, iconName: .checkCircle, tint: AreaMatrixTheme.Colors.teal) : pending(title)
    }
}
