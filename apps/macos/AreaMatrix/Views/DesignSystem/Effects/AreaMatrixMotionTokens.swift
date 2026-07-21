import SwiftUI

/// Shared motion timing and intensity tokens. Pages must consume these instead of hardcoding durations.
enum AreaMatrixMotionTokens {
    enum Duration {
        static let flash: Double = 0.15
        static let quickFade: Double = 0.2
        static let entrance: Double = 0.5
        static let themeToggle: Double = 0.3
        static let hoverSettle: Double = 0.4
        static let sceneParallax: Double = 0.16
        static let sceneEnterExit: Double = 0.6
        static let overlayFade: Double = 0.8
        static let progressStep: Double = 0.8
        static let deepDive: Double = 0.6
        static let pulseAura: Double = 2.5
        static let glowBreath: Double = 1.25
        static let shimmerSweep: Double = 3.0
        static let textShimmer: Double = 4.0
        static let cursorBlink: Double = 0.45
        static let scanRipple: Double = 1.2
        static let blobBreathShort: Double = 6.0
        static let blobBreathMid: Double = 7.0
        static let blobBreathLong: Double = 8.0
        static let blobBreathExtra: Double = 9.0
        static let ambientOrbit: Double = 60.0
    }

    enum Spring {
        static let response: Double = 0.6
        static let damping: Double = 0.8
        static let hoverResponse: Double = 0.3
        static let hoverDamping: Double = 0.6
        static let sceneFlowDamping: Double = 0.82
        static let themeSpinResponse: Double = 0.5
        static let themeSpinDamping: Double = 0.6
        static let magneticStiffness: Double = 150
        static let magneticDamping: Double = 12
        static let dropBounceStiffness: Double = 170
        static let dropBounceDamping: Double = 10
    }

    enum EntranceDelay {
        static let immediate: Double = 0
        static let header: Double = 0.05
        static let body: Double = 0.15
        static let footer: Double = 0.25
        static let featureCard1: Double = 0.3
        static let featureCard2: Double = 0.55
        static let featureCard3: Double = 0.8
        static let staggerStep: Double = 0.08
    }

    enum Intensity {
        static let magneticDefault: CGFloat = 0.2
        static let magneticCTA: CGFloat = 0.15
        static let pulseAuraMaxScale: CGFloat = 1.7
        static let pulseAuraCTAMaxScale: CGFloat = 1.5
        static let deepDiveScanScale: CGFloat = 2.5
        static let entranceOffsetY: CGFloat = 12
        static let hoverScale: CGFloat = 1.04
        static let pressScale: CGFloat = 0.96
    }

    /// Ambient blob / vignette strength for different product surfaces.
    enum AmbientStrength: Equatable {
        case full
        case standard
        case subdued

        var opacityScale: Double {
            switch self {
            case .full: 1.0
            case .standard: 0.85
            case .subdued: 0.55
            }
        }
    }
}
