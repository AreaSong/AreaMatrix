import SwiftUI

/// Shared motion timing and intensity tokens used by the macOS design system.
public enum AreaMatrixMotionTokens {
    public enum Duration {
        public static let flash: Double = 0.15
        public static let quickFade: Double = 0.2
        public static let entrance: Double = 0.5
        public static let themeToggle: Double = 0.3
        public static let hoverSettle: Double = 0.4
        public static let sceneParallax: Double = 0.16
        public static let sceneEnterExit: Double = 0.6
        public static let overlayFade: Double = 0.8
        public static let progressStep: Double = 0.8
        public static let deepDive: Double = 0.6
        public static let pulseAura: Double = 2.5
        public static let glowBreath: Double = 1.25
        public static let shimmerSweep: Double = 3.0
        public static let textShimmer: Double = 4.0
        public static let cursorBlink: Double = 0.45
        public static let scanRipple: Double = 1.2
        public static let blobBreathShort: Double = 6.0
        public static let blobBreathMid: Double = 7.0
        public static let blobBreathLong: Double = 8.0
        public static let blobBreathExtra: Double = 9.0
        public static let ambientOrbit: Double = 60.0
    }

    public enum Spring {
        public static let response: Double = 0.6
        public static let damping: Double = 0.8
        public static let hoverResponse: Double = 0.3
        public static let hoverDamping: Double = 0.6
        public static let sceneFlowDamping: Double = 0.82
        public static let themeSpinResponse: Double = 0.5
        public static let themeSpinDamping: Double = 0.6
        public static let magneticStiffness: Double = 150
        public static let magneticDamping: Double = 12
        public static let dropBounceStiffness: Double = 170
        public static let dropBounceDamping: Double = 10
    }

    public enum EntranceDelay {
        public static let immediate: Double = 0
        public static let header: Double = 0.05
        public static let body: Double = 0.15
        public static let footer: Double = 0.25
        public static let featureCard1: Double = 0.3
        public static let featureCard2: Double = 0.55
        public static let featureCard3: Double = 0.8
        public static let staggerStep: Double = 0.08
    }

    public enum Intensity {
        public static let magneticDefault: CGFloat = 0.2
        public static let magneticCTA: CGFloat = 0.15
        public static let pulseAuraMaxScale: CGFloat = 1.7
        public static let pulseAuraCTAMaxScale: CGFloat = 1.5
        public static let deepDiveScanScale: CGFloat = 2.5
        public static let entranceOffsetY: CGFloat = 12
        public static let hoverScale: CGFloat = 1.04
        public static let pressScale: CGFloat = 0.96
    }

    public enum AmbientStrength: Equatable, Sendable {
        case full
        case standard
        case subdued

        public var opacityScale: Double {
            switch self {
            case .full: 1.0
            case .standard: 0.85
            case .subdued: 0.55
            }
        }
    }
}
