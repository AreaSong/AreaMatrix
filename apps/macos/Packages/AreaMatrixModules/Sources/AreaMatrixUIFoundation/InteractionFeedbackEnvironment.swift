import SwiftUI

private struct AreaMatrixInteractionFeedbackKey: EnvironmentKey {
    static let defaultValue: any AreaMatrixInteractionFeedbackPerforming = AreaMatrixNoopInteractionFeedback()
}

public extension EnvironmentValues {
    /// Platform-neutral interaction feedback supplied by the App composition root.
    var areaMatrixInteractionFeedback: any AreaMatrixInteractionFeedbackPerforming {
        get { self[AreaMatrixInteractionFeedbackKey.self] }
        set { self[AreaMatrixInteractionFeedbackKey.self] = newValue }
    }
}
