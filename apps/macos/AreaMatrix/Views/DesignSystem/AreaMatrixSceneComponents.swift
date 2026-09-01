import AreaMatrixUIFoundation
import SwiftUI

struct AreaMatrixSceneText: View {
    let title: String
    let description: String
    var gradient: LinearGradient?
    var maxWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 12) {
            AreaMatrixDecodedText(text: title, gradient: gradient)
                .font(.system(size: 22, weight: .semibold))
                .tracking(0.5)
                .areaMatrixSceneTextMotion(delay: 0.05)
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .areaMatrixSceneTextMotion(delay: 0.1)
        }
        .frame(maxWidth: maxWidth)
    }
}

struct AreaMatrixLaunchBrandVisual: View {
    var darkName = "AreaMatrixLogoLockupDark"
    var lightName = "AreaMatrixLogoLockupLight"
    var height: CGFloat = 100
    var frameHeight: CGFloat = 220
    var shadowColor = AreaMatrixTheme.Colors.teal

    @State private var logoEntered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        AreaMatrixCrossfadeAssetImage(
            darkName: darkName,
            lightName: lightName,
            width: nil,
            height: height
        )
        .shadow(
            color: shadowColor.opacity(reduceTransparency ? 0 : 0.4),
            radius: reduceTransparency ? 0 : 16,
            y: reduceTransparency ? 0 : 12
        )
        .offset(y: reduceMotion || logoEntered ? 0 : -20)
        .scaleEffect(reduceMotion || logoEntered ? 1 : 0.85)
        .animation(
            reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.55).delay(0.2),
            value: logoEntered
        )
        .frame(height: frameHeight)
        .areaMatrixSceneVisualMotion()
        .onAppear { logoEntered = true }
    }
}

struct AreaMatrixLaunchCopyText: View {
    let title: String
    let description: String
    var highlightToken = AreaMatrixTheme.Colors.tealText
    var maxWidth: CGFloat = 560

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var subtitleBreathing = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(0.5)
                .areaMatrixTextShimmer(highlight: highlightToken.resolve(colorScheme))
                .areaMatrixSceneTextMotion(delay: 0.05)

            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(reduceMotion || reduceTransparency ? 1.0 : (subtitleBreathing ? 0.72 : 1.0))
                .animation(
                    reduceMotion || !subtitleBreathing
                        ? nil
                        : .easeInOut(duration: 3).repeatForever(autoreverses: true),
                    value: subtitleBreathing
                )
                .areaMatrixSceneTextMotion(delay: 0.15)
        }
        .frame(maxWidth: maxWidth)
        .onAppear(perform: updateSubtitleMotion)
        .onChange(of: reduceMotion) { _, _ in updateSubtitleMotion() }
        .onChange(of: reduceTransparency) { _, _ in updateSubtitleMotion() }
        .onDisappear(perform: stopSubtitleMotion)
    }

    private func updateSubtitleMotion() {
        stopSubtitleMotion()
        guard !reduceMotion, !reduceTransparency else { return }
        subtitleBreathing = true
    }

    private func stopSubtitleMotion() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            subtitleBreathing = false
        }
    }
}

struct AreaMatrixFloatingSymbolSpec {
    let name: String
    let size: CGFloat
    let offset: CGSize
    let duration: Double
    let delay: Double

    static let documentCluster = [
        AreaMatrixFloatingSymbolSpec(
            name: "doc.text.fill",
            size: 14,
            offset: CGSize(width: -100, height: -25),
            duration: 2.2,
            delay: 0
        ),
        AreaMatrixFloatingSymbolSpec(
            name: "photo.fill",
            size: 12,
            offset: CGSize(width: 105, height: 15),
            duration: 2.6,
            delay: 0.5
        ),
        AreaMatrixFloatingSymbolSpec(
            name: "tablecells.fill",
            size: 13,
            offset: CGSize(width: -85, height: 45),
            duration: 1.9,
            delay: 1.0
        )
    ]
}

struct AreaMatrixFolderLaunchVisual: View {
    var auraColor = AreaMatrixTheme.Colors.emeraldLight
    var fillColor = AreaMatrixTheme.Colors.emerald.opacity(0.15)
    var strokeColor = AreaMatrixTheme.Colors.tealBright
    var glowColor = AreaMatrixTheme.Colors.emerald
    var symbols = AreaMatrixFloatingSymbolSpec.documentCluster

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            pulsePlate

            ForEach(symbols, id: \.name) { spec in
                floatingSymbol(spec)
            }

            folderShape
        }
        .frame(height: 220)
        .areaMatrixSceneVisualMotion()
        .onAppear { isAnimating = !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in
            isAnimating = !reduced
        }
    }

    private var pulsePlate: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color.clear)
            .frame(width: 200, height: 144)
            .areaMatrixPulseAura(color: auraColor)
    }

    private var folderShape: some View {
        AreaMatrixFolderShape(tabWidth: 64, tabHeight: 24, cornerRadius: 16)
            .fill(reduceTransparency ? AreaMatrixTheme.Colors.emerald : fillColor)
            .overlay(
                AreaMatrixFolderShape(tabWidth: 64, tabHeight: 24, cornerRadius: 16)
                    .stroke(strokeColor, lineWidth: 3)
            )
            .frame(width: 180, height: 148)
            .overlay(folderPlus)
            .offset(y: -12)
            .shadow(color: glowColor.opacity(isAnimating ? 0.6 : 0.3), radius: isAnimating ? 40 : 20)
            .scaleEffect(isAnimating ? 1.05 : 1.0)
            .animation(
                reduceMotion || !isAnimating
                    ? nil
                    : .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                value: isAnimating
            )
    }

    private var folderPlus: some View {
        Image(systemName: "plus")
            .font(.system(size: 36, weight: .semibold))
            .foregroundColor(.white)
            .shadow(color: .white.opacity(0.9), radius: isAnimating ? 28 : 8)
            .animation(
                reduceMotion || !isAnimating
                    ? nil
                    : .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .offset(y: 12)
    }

    private func floatingSymbol(_ spec: AreaMatrixFloatingSymbolSpec) -> some View {
        Image(systemName: spec.name)
            .font(.system(size: spec.size))
            .foregroundColor(strokeColor.opacity(reduceTransparency ? 1 : 0.5))
            .offset(spec.offset)
            .offset(y: isAnimating ? -6 : 6)
            .opacity(reduceTransparency ? 1 : (isAnimating ? 0.7 : 0.2))
            .animation(
                reduceMotion || !isAnimating
                    ? nil
                    : .easeInOut(duration: spec.duration)
                    .repeatForever(autoreverses: true)
                    .delay(spec.delay),
                value: isAnimating
            )
    }
}
