import SwiftUI

struct InitializingStepRow {
    let title: String
    let systemImage: String
    let tint: Color

    static func pending(_ title: String) -> InitializingStepRow {
        InitializingStepRow(title: title, systemImage: "clock", tint: .secondary)
    }

    static func running(_ title: String, when condition: Bool) -> InitializingStepRow {
        condition ? InitializingStepRow(title: title, systemImage: "arrow.triangle.2.circlepath", tint: .accentColor)
            : pending(title)
    }

    static func completed(_ title: String, when condition: Bool) -> InitializingStepRow {
        condition ? InitializingStepRow(title: title, systemImage: "checkmark.circle", tint: .green) : pending(title)
    }
}
