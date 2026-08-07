import SwiftUI

/// Platform-neutral interaction effects consumed by reusable SwiftUI controls.
///
/// The App target supplies the AppKit implementation at the composition root;
/// the foundation package only defines the contract and a side-effect-free
/// fallback for previews and isolated view construction.
public enum AreaMatrixAppearancePreference: Sendable {
    case system
    case light
    case dark
}

public enum AreaMatrixHapticFeedback: Sendable {
    case alignment
    case levelChange
}

public protocol AreaMatrixInteractionFeedbackPerforming {
    @MainActor
    func applyAppearance(_ preference: AreaMatrixAppearancePreference)
    @MainActor
    func setPointingCursor(active: Bool)
    @MainActor
    func performHaptic(_ feedback: AreaMatrixHapticFeedback)
}

/// A safe environment default that keeps previews and tests free of AppKit
/// side effects. Production composition replaces it with the platform adapter.
public struct AreaMatrixNoopInteractionFeedback: AreaMatrixInteractionFeedbackPerforming {
    public init() {}

    @MainActor
    public func applyAppearance(_: AreaMatrixAppearancePreference) {}

    @MainActor
    public func setPointingCursor(active _: Bool) {}

    @MainActor
    public func performHaptic(_: AreaMatrixHapticFeedback) {}
}
