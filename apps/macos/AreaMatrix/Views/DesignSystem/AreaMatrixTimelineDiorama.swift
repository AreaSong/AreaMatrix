import AreaMatrixUIFoundation
import SwiftUI

struct AreaMatrixTimelineDiorama: View {
    @State private var showNewName = false
    @State private var isSpinning = false
    @State private var particleFlying = false
    @State private var typedMarkdownLines: [AreaMatrixTypedMarkdownLine] = []
    @State private var timerTask: Task<Void, Never>?
    @State private var typingTask: Task<Void, Never>?
    @State private var animationStartTask: Task<Void, Never>?
    @State private var animationGeneration = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var markdownTypewriterLines: [(String, Color)] {
        [
            ("## Documents", Color(red: 0.337, green: 0.612, blue: 0.839)),
            ("- Finance/Invoice.pdf", colorScheme == .dark
                ? Color(red: 0.306, green: 0.788, blue: 0.69)
                : AreaMatrixTheme.Colors.tealDeep),
            ("- Design/brand.sketch", Color(red: 0.808, green: 0.569, blue: 0.471))
        ]
    }

    var body: some View {
        HStack(spacing: 20) {
            finderWindow
            syncBridge
            markdownWindow
        }
        .frame(height: 220)
        .onChange(of: sceneVisibility, initial: true) { _, newPhase in
            if newPhase.isVisible {
                restartAnimations()
            } else {
                stopAnimations()
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            if sceneVisibility.isVisible {
                restartAnimations()
            } else {
                stopAnimations()
            }
        }
        .onDisappear(perform: stopAnimations)
    }

    private func restartAnimations() {
        stopAnimations()
        showNewName = false
        typedMarkdownLines = []
        isSpinning = false
        particleFlying = false
        guard sceneVisibility.isVisible else { return }
        guard !reduceMotion else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                showNewName = true
                typedMarkdownLines = markdownTypewriterLines.map {
                    AreaMatrixTypedMarkdownLine(text: $0.0, color: $0.1)
                }
            }
            return
        }
        let generation = animationGeneration
        startCycle(generation: generation)
        startTyping(generation: generation)
        animationStartTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, isCurrent(generation) else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { isSpinning = true }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) { particleFlying = true }
        }
    }

    private func stopAnimations() {
        animationGeneration += 1
        animationStartTask?.cancel()
        timerTask?.cancel()
        typingTask?.cancel()
        animationStartTask = nil
        timerTask = nil
        typingTask = nil
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isSpinning = false
            particleFlying = false
        }
    }

    private func startCycle(generation: Int) {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, isCurrent(generation) else { return }
                withAnimation(.easeInOut(duration: 0.4)) { showNewName.toggle() }
            }
        }
    }

    private func startTyping(generation: Int) {
        typingTask?.cancel()
        typingTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) {
                    typedMarkdownLines = []
                }

                for source in markdownTypewriterLines {
                    guard await typeLine(source, generation: generation) else { return }
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled, isCurrent(generation) else { return }
                }

                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled, isCurrent(generation) else { return }
            }
        }
    }

    private func typeLine(_ source: (String, Color), generation: Int) async -> Bool {
        guard isCurrent(generation) else { return false }
        let line = AreaMatrixTypedMarkdownLine(text: "", color: source.1)
        withAnimation(.easeOut(duration: 0.25)) {
            typedMarkdownLines.append(line)
        }

        for character in source.0 {
            try? await Task.sleep(for: .milliseconds(34))
            guard !Task.isCancelled, isCurrent(generation) else { return false }
            if let index = typedMarkdownLines.firstIndex(where: { $0.id == line.id }) {
                typedMarkdownLines[index].text.append(character)
            }
        }

        return true
    }

    private func isCurrent(_ generation: Int) -> Bool {
        accessibilityPolicy.allowsDelayedAnimationCommit(
            generation: generation,
            currentGeneration: animationGeneration,
            isVisible: sceneVisibility.isVisible
        )
    }

    private var accessibilityPolicy: AreaMatrixAccessibilityMotionPolicy {
        AreaMatrixAccessibilityMotionPolicy(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }

    private var finderWindow: some View {
        AreaMatrixMiniWindow(title: L10n.string("Finder"), width: 180, height: 150) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 40)
                VStack(alignment: .leading) {
                    finderFileRow
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    private var finderFileRow: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [AreaMatrixTheme.Colors.tealBright, AreaMatrixTheme.Colors.teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 10, height: 10))
            renamedTextPair(primaryColor: colorScheme == .dark ? .green : AreaMatrixTheme.Colors.emeraldDeep)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(8)
        .background(
            showNewName
                ? AreaMatrixTheme.Colors.teal.opacity(reduceTransparency ? 0.8 : 0.2)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }

    private var markdownWindow: some View {
        AreaMatrixMiniWindow(title: L10n.string("AREAMATRIX.md"), width: 220, height: 150, useDarkBackground: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("# Index Graph"))
                    .foregroundColor(Color(red: 0.337, green: 0.612, blue: 0.839))
                HStack(spacing: 4) {
                    Text(L10n.string("- [x]"))
                        .foregroundColor(Color(red: 0.808, green: 0.569, blue: 0.471))
                    renamedTextPair(primaryColor: markdownRenameColor, highlighted: true)
                }
                ForEach(typedMarkdownLines) { line in
                    Text(line.text)
                        .foregroundColor(line.color)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(14)
            .font(.system(size: 11, design: .monospaced))
        }
    }

    private var syncBridge: some View {
        ZStack {
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 8]))
                .foregroundColor(AreaMatrixTheme.Colors.coral.opacity(0.4))
                .frame(height: 2)
            movingParticle(
                color: AreaMatrixTheme.Colors.coral,
                size: 6,
                startX: -25,
                endX: 25,
                delay: 0
            )
            movingParticle(
                color: AreaMatrixTheme.Colors.tealBright,
                size: 5,
                startX: 25,
                endX: -25,
                delay: 1
            )
            bridgeCore
        }
        .frame(width: 60)
    }

    private func movingParticle(color: Color, size: CGFloat, startX: CGFloat, endX: CGFloat,
                                delay: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: 8)
            .offset(x: particleFlying ? endX : startX)
            .opacity(particleFlying ? 0 : 1)
            .animation(
                reduceMotion || !particleFlying
                    ? nil
                    : .easeInOut(duration: 2).repeatForever(autoreverses: false).delay(delay),
                value: particleFlying
            )
    }

    private var bridgeCore: some View {
        Circle()
            .fill(
                reduceTransparency
                    ? AnyShapeStyle(colorScheme == .dark ? Color.black : Color.white)
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(AreaMatrixTheme.Colors.coral.opacity(0.5)))
            .overlay(
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(AreaMatrixTheme.Colors.coral)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
            )
    }

    private func renamedTextPair(primaryColor: Color, highlighted: Bool = false) -> some View {
        ZStack(alignment: .leading) {
            Text("Draft_v1.md")
                .opacity(showNewName ? 0 : 1)
            Text("Final_v2.md")
                .foregroundColor(primaryColor)
                .padding(.horizontal, highlighted ? 4 : 0)
                .background(
                    highlighted && showNewName
                        ? primaryColor.opacity(reduceTransparency ? 0.9 : 0.3)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .opacity(showNewName ? 1 : 0)
        }
    }

    private var markdownRenameColor: Color {
        colorScheme == .dark ? Color(red: 0.306, green: 0.788, blue: 0.69) : AreaMatrixTheme.Colors.tealDeep
    }
}

private struct AreaMatrixTypedMarkdownLine: Identifiable {
    let id = UUID()
    var text: String
    let color: Color
}
