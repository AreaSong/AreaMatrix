import SwiftUI

/// Shared color token that resolves a light and dark value at the point of use.
public struct AreaMatrixColorToken: Sendable {
    public let light: Color
    public let dark: Color

    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    public func resolve(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}

public struct AreaMatrixParallax: Equatable, Sendable {
    public var horizontal: CGFloat
    public var vertical: CGFloat

    public init(horizontal: CGFloat, vertical: CGFloat) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let zero = AreaMatrixParallax(horizontal: 0, vertical: 0)
}

public enum AreaMatrixAmbientScene: Int, CaseIterable, Sendable {
    case home
    case classify
    case security
    case tracking
    case help
    case start

    public var accent: AreaMatrixTheme.Accent {
        switch self {
        case .home: .teal
        case .classify: .tealBright
        case .security: .gold
        case .tracking: .coral
        case .help: .purple
        case .start: .emerald
        }
    }
}

public enum AreaMatrixTheme {
    public enum Accent: Sendable {
        case teal
        case tealBright
        case gold
        case coral
        case purple
        case emerald

        public var color: Color {
            switch self {
            case .teal: Colors.teal
            case .tealBright: Colors.tealBright
            case .gold: Colors.gold
            case .coral: Colors.coral
            case .purple: Colors.purple
            case .emerald: Colors.emerald
            }
        }

        public var textToken: AreaMatrixColorToken {
            switch self {
            case .teal, .tealBright: Colors.tealText
            case .gold: Colors.goldText
            case .coral: Colors.coralText
            case .purple: Colors.purpleText
            case .emerald: Colors.emeraldText
            }
        }
    }

    public enum Colors {
        public static let teal = Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255)
        public static let tealBright = Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255)
        public static let gold = Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255)
        public static let coral = Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255)
        public static let purple = Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255)
        public static let purpleLight = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
        public static let emerald = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
        public static let emeraldLight = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)

        public static let tealDeep = Color(red: 10 / 255, green: 120 / 255, blue: 106 / 255)
        public static let emeraldDeep = Color(red: 8 / 255, green: 115 / 255, blue: 82 / 255)
        public static let goldDeep = Color(red: 166 / 255, green: 120 / 255, blue: 13 / 255)
        public static let coralDeep = Color(red: 180 / 255, green: 70 / 255, blue: 50 / 255)
        public static let purpleDeep = Color(red: 100 / 255, green: 30 / 255, blue: 180 / 255)

        public static let tealText = AreaMatrixColorToken(light: tealDeep, dark: tealBright)
        public static let emeraldText = AreaMatrixColorToken(light: emeraldDeep, dark: emeraldLight)
        public static let goldText = AreaMatrixColorToken(light: goldDeep, dark: gold)
        public static let coralText = AreaMatrixColorToken(light: coralDeep, dark: coral)
        public static let purpleText = AreaMatrixColorToken(light: purpleDeep, dark: purple)

        public static let backgroundTop = AreaMatrixColorToken(
            light: Color(red: 252 / 255, green: 253 / 255, blue: 255 / 255),
            dark: Color(red: 15 / 255, green: 20 / 255, blue: 28 / 255)
        )
        public static let backgroundBottom = AreaMatrixColorToken(
            light: Color(red: 244 / 255, green: 246 / 255, blue: 250 / 255),
            dark: Color(red: 5 / 255, green: 8 / 255, blue: 12 / 255)
        )

        public static let sceneSpectrum = [teal, tealBright, gold, coral, purple, emerald]

        public static func backgroundGradient(for colorScheme: ColorScheme) -> [Color] {
            [backgroundTop.resolve(colorScheme), backgroundBottom.resolve(colorScheme)]
        }
    }

    public enum Gradients {
        public static func appBackground(for colorScheme: ColorScheme) -> LinearGradient {
            LinearGradient(
                colors: Colors.backgroundGradient(for: colorScheme),
                startPoint: .top,
                endPoint: .bottom
            )
        }

        public static func primaryAction(accent: Color = Colors.teal) -> LinearGradient {
            LinearGradient(
                colors: [Colors.tealBright, accent],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        public static func textAccent(_ first: Color, _ second: Color) -> LinearGradient {
            LinearGradient(colors: [first, second], startPoint: .leading, endPoint: .trailing)
        }
    }

    public enum Surfaces {
        public static func windowBorder(accent: Color, colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? accent.opacity(0.2) : accent.opacity(0.12)
        }

        public static func featureSpotlight(isHovered: Bool, colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.08 : 0.05) : 0)
        }

        public static func windowShadow(colorScheme: ColorScheme) -> Color {
            .black.opacity(colorScheme == .dark ? 0.8 : 0.18)
        }
    }
}
