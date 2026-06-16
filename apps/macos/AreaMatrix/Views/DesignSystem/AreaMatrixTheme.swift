import SwiftUI

struct AreaMatrixColorToken {
    let light: Color
    let dark: Color

    func resolve(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}

struct AreaMatrixParallax: Equatable {
    var horizontal: CGFloat
    var vertical: CGFloat

    static let zero = AreaMatrixParallax(horizontal: 0, vertical: 0)
}

enum AreaMatrixAmbientScene: Int, CaseIterable {
    case home
    case classify
    case security
    case tracking
    case help
    case start

    var accent: AreaMatrixTheme.Accent {
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

enum AreaMatrixTheme {
    enum Accent {
        case teal
        case tealBright
        case gold
        case coral
        case purple
        case emerald

        var color: Color {
            switch self {
            case .teal: Colors.teal
            case .tealBright: Colors.tealBright
            case .gold: Colors.gold
            case .coral: Colors.coral
            case .purple: Colors.purple
            case .emerald: Colors.emerald
            }
        }

        var textToken: AreaMatrixColorToken {
            switch self {
            case .teal, .tealBright: Colors.tealText
            case .gold: Colors.goldText
            case .coral: Colors.coralText
            case .purple: Colors.purpleText
            case .emerald: Colors.emeraldText
            }
        }
    }

    enum Colors {
        static let teal = Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255)
        static let tealBright = Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255)
        static let gold = Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255)
        static let coral = Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255)
        static let purple = Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255)
        static let purpleLight = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
        static let emerald = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
        static let emeraldLight = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)

        static let tealDeep = Color(red: 10 / 255, green: 120 / 255, blue: 106 / 255)
        static let emeraldDeep = Color(red: 8 / 255, green: 115 / 255, blue: 82 / 255)
        static let goldDeep = Color(red: 166 / 255, green: 120 / 255, blue: 13 / 255)
        static let coralDeep = Color(red: 180 / 255, green: 70 / 255, blue: 50 / 255)
        static let purpleDeep = Color(red: 100 / 255, green: 30 / 255, blue: 180 / 255)

        static let tealText = AreaMatrixColorToken(light: tealDeep, dark: tealBright)
        static let emeraldText = AreaMatrixColorToken(light: emeraldDeep, dark: emeraldLight)
        static let goldText = AreaMatrixColorToken(light: goldDeep, dark: gold)
        static let coralText = AreaMatrixColorToken(light: coralDeep, dark: coral)
        static let purpleText = AreaMatrixColorToken(light: purpleDeep, dark: purple)

        static let backgroundTop = AreaMatrixColorToken(
            light: Color(red: 250 / 255, green: 251 / 255, blue: 248 / 255),
            dark: Color(red: 13 / 255, green: 40 / 255, blue: 35 / 255)
        )
        static let backgroundBottom = AreaMatrixColorToken(
            light: Color(red: 242 / 255, green: 245 / 255, blue: 240 / 255),
            dark: Color(red: 7 / 255, green: 21 / 255, blue: 19 / 255)
        )

        static func backgroundGradient(for colorScheme: ColorScheme) -> [Color] {
            [
                backgroundTop.resolve(colorScheme),
                backgroundBottom.resolve(colorScheme)
            ]
        }
    }

    enum Gradients {
        static func appBackground(for colorScheme: ColorScheme) -> LinearGradient {
            LinearGradient(
                colors: Colors.backgroundGradient(for: colorScheme),
                startPoint: .top,
                endPoint: .bottom
            )
        }

        static func primaryAction(accent: Color = Colors.teal) -> LinearGradient {
            LinearGradient(
                colors: [Colors.tealBright, accent],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        static func textAccent(_ first: Color, _ second: Color) -> LinearGradient {
            LinearGradient(colors: [first, second], startPoint: .leading, endPoint: .trailing)
        }
    }

    enum Surfaces {
        static func windowBorder(accent: Color, colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? accent.opacity(0.2) : accent.opacity(0.12)
        }

        static func featureSpotlight(isHovered: Bool, colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.08 : 0.05) : 0)
        }

        static func windowShadow(colorScheme: ColorScheme) -> Color {
            .black.opacity(colorScheme == .dark ? 0.8 : 0.18)
        }
    }
}
