import SwiftUI

struct AreaMatrixTerminalLine: Identifiable {
    let id = UUID()
    var text: String
    let colorToken: AreaMatrixColorToken
}

extension [AreaMatrixTerminalLine] {
    mutating func appendTerminalLine(
        _ line: AreaMatrixTerminalLine,
        maxVisibleLines: Int = 5,
        appendAnimation: Animation = .easeOut(duration: 0.25)
    ) {
        withAnimation(appendAnimation) {
            append(line)
            if count > maxVisibleLines {
                removeFirst()
            }
        }
    }

    mutating func appendTerminalCharacter(_ character: Character, toLineWithID id: UUID) {
        if let index = firstIndex(where: { $0.id == id }) {
            self[index].text.append(character)
        }
    }
}

enum AreaMatrixTerminalLogTypewriter {
    static func type(
        _ text: String,
        characterDelay: Duration = .milliseconds(18),
        onCharacter: @MainActor @escaping (Character) -> Void
    ) async -> Bool {
        for character in text {
            try? await Task.sleep(for: characterDelay)
            guard !Task.isCancelled else { return false }
            await onCharacter(character)
        }

        return true
    }
}

struct AreaMatrixWhiteFlashOverlay: View {
    let isVisible: Bool

    var body: some View {
        Color.white
            .ignoresSafeArea()
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isVisible)
    }
}

struct AreaMatrixScanOverlay: View {
    let isScanning: Bool
    let terminalLines: [AreaMatrixTerminalLine]
    let cursorColorToken: AreaMatrixColorToken
    let progressFraction: CGFloat
    let accent: Color
    var darkLogoName = "AreaMatrixLogoMarkDark"
    var lightLogoName = "AreaMatrixLogoMarkLight"
    var scanColors = AreaMatrixTheme.Colors.sceneSpectrum

    @Environment(\.colorScheme) private var colorScheme
    @State private var cursorVisible = true
    @State private var logoPulsing = false
    @State private var rippleScale: CGFloat = 0.1
    @State private var rippleOpacity: Double = 0

    var body: some View {
        ZStack {
            overlayBackdrop
            movingColorWash
            rippleLayer
            scanContent
        }
        .scaleEffect(isScanning ? 1 : 0.9)
        .opacity(isScanning ? 1 : 0)
        .animation(.areaMatrixSpring.delay(0.2), value: isScanning)
        .onAppear {
            logoPulsing = true
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }

    private var overlayBackdrop: some View {
        Rectangle()
            .fill(Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15))
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
    }

    private var movingColorWash: some View {
        LinearGradient(
            colors: effectiveScanColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 6000)
        .offset(x: -4000 * progressFraction)
        .opacity(colorScheme == .dark ? 0.25 : 0.2)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: progressFraction)
    }

    private var rippleLayer: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accent.opacity(0.8), accent.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 200
                )
            )
            .frame(width: 400, height: 400)
            .scaleEffect(rippleScale)
            .opacity(rippleOpacity)
            .onChange(of: accent) { _, _ in
                rippleScale = 0.1
                rippleOpacity = 0.8
                withAnimation(.easeOut(duration: 1.2)) {
                    rippleScale = 4.0
                    rippleOpacity = 0.0
                }
            }
            .allowsHitTesting(false)
    }

    private var scanContent: some View {
        VStack(spacing: 40) {
            scanRing
            terminalLog
            progressBar
        }
    }

    private var scanRing: some View {
        ZStack {
            Circle()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), lineWidth: 2)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0.0, to: 0.32)
                .stroke(scanRingGradient, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(isScanning ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)

            AreaMatrixCrossfadeAssetImage(
                darkName: darkLogoName,
                lightName: lightLogoName,
                width: 80,
                height: 80
            )
            .scaleEffect(logoPulsing ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: logoPulsing)
            .shadow(color: accent.opacity(0.5), radius: 12)
        }
    }

    private var scanRingGradient: AngularGradient {
        AngularGradient(
            colors: effectiveScanColors + [effectiveScanColors.first ?? accent],
            center: .center
        )
    }

    private var terminalLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(terminalLines, id: \.id) { line in
                terminalLine(line)
            }

            Rectangle()
                .fill(cursorColor)
                .frame(width: 8, height: 14)
                .opacity(cursorVisible ? 1 : 0)
                .shadow(color: cursorColor.opacity(0.5), radius: 4)
        }
        .frame(width: 340, height: 100, alignment: .bottomLeading)
        .clipped()
    }

    private func terminalLine(_ line: AreaMatrixTerminalLine) -> some View {
        let color = line.colorToken.resolve(colorScheme)
        return Text(line.text)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .opacity(line.text.isEmpty ? 0 : 1)
            .shadow(color: color.opacity(0.4), radius: 4)
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(0.15))
                .frame(width: 340, height: 3)
                .animation(.easeInOut(duration: 0.8), value: accent)

            LinearGradient(
                colors: [progressStartColor, accent],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(0, 340 * progressFraction), height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: accent.opacity(0.6), radius: 8)
            .animation(.easeOut(duration: 0.3), value: progressFraction)
        }
    }

    private var cursorColor: Color {
        cursorColorToken.resolve(colorScheme)
    }

    private var effectiveScanColors: [Color] {
        scanColors.isEmpty ? [accent] : scanColors
    }

    private var progressStartColor: Color {
        effectiveScanColors.first ?? accent
    }
}

struct AreaMatrixDropOverlay: View {
    var message = L10n.string("import.drop.releaseToImport")
    var iconName = "tray.and.arrow.down"
    var accent = AreaMatrixTheme.Colors.tealBright

    @State private var isBouncing = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 46, weight: .light))
                .foregroundColor(accent)
                .offset(y: isBouncing ? -6 : 0)
                .animation(
                    .interpolatingSpring(stiffness: 170, damping: 10).repeatForever(autoreverses: false),
                    value: isBouncing
                )
            Text(message)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.18))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .onAppear { isBouncing = true }
    }
}

extension View {
    /// Onboarding step panel — shared glass content panel with fixed width.
    func areaMatrixOnboardingPanel() -> some View {
        areaMatrixGlassContentPanel(width: 580)
    }
}
