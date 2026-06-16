import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum WelcomeWindowMetrics {
    static let width: CGFloat = 860
    static let height: CGFloat = 640
    static let cornerRadius: CGFloat = 12
}

private struct WelcomeFeatureCardSpec {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let stage: WelcomeStage
    let entranceDelay: Double
}

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeStage: WelcomeStage = .default
    @State private var hoverStage: WelcomeStage?
    @State private var isScanning = false
    @State private var isExiting = false
    @State private var isDeepDiving = false
    @State private var whiteFlash = false
    @State private var isDragTargeted = false
    @State private var isCtaHovered = false
    @State private var isLearnMoreHovered = false
    @State private var footerEntered = false

    static var hasPlayedLaunchAnimation = false
    @State private var mouseParallax = WelcomeParallax.zero
    @State private var scanTerminalLines = [
        WelcomeTerminalLine(text: "等待系统指令...", color: AreaMatrixTheme.Colors.tealBright)
    ]
    @State private var scanCursorColor = AreaMatrixTheme.Colors.tealBright
    @State private var scanTask: Task<Void, Never>?
    @State private var hoverResetTask: Task<Void, Never>?
    @State private var scanProgressFraction: CGFloat = 0
    @FocusState private var isLearnMoreFocused: Bool
    @FocusState private var isChooseFolderFocused: Bool
    /// 用户手动切换的主题偏好：nil = 跟随系统
    @State private var themeOverride: ColorScheme?
    @State private var shimmerPhase: CGFloat = -1.5

    /// Derived stage to show
    private var displayStage: WelcomeStage {
        hoverStage ?? activeStage
    }

    var body: some View {
        welcomeSurface
            .frame(
                minWidth: WelcomeWindowMetrics.width,
                idealWidth: WelcomeWindowMetrics.width,
                maxWidth: .infinity,
                minHeight: WelcomeWindowMetrics.height,
                idealHeight: WelcomeWindowMetrics.height,
                maxHeight: .infinity
            )
            .background(AreaMatrixWindowChromeObserver())
            .preferredColorScheme(themeOverride)
            .onAppear {
                if !Self.hasPlayedLaunchAnimation {
                    footerEntered = true
                    Self.hasPlayedLaunchAnimation = true
                } else {
                    footerEntered = true
                }
            }
            .onDisappear {
                scanTask?.cancel()
                hoverResetTask?.cancel()
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) {
                navigateStage(direction: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                navigateStage(direction: 1)
                return .handled
            }
    }

    private var welcomeSurface: some View {
        ZStack {
            WelcomeAmbientBackground(stage: displayStage, parallax: mouseParallax)

            welcomeContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WelcomeWindowMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WelcomeWindowMetrics.cornerRadius, style: .continuous)
                .stroke(windowBorderColor, lineWidth: 1)
                .animation(.easeInOut(duration: 0.8), value: displayStage)
        )
        .shadow(
            color: AreaMatrixTheme.Surfaces.windowShadow(colorScheme: colorScheme),
            radius: 60,
            x: mouseParallax.horizontal * -10,
            y: mouseParallax.vertical * -10 + 30
        )
        .blur(radius: isScanning ? 12 : 0)
        .scaleEffect(isScanning ? 0.92 : 1)
        .opacity(isScanning ? 0.05 : 1)
        .ignoresSafeArea(.container, edges: .all)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isScanning)
        .overlay {
            if isScanning {
                WelcomeScanOverlayView(
                    isScanning: isScanning,
                    terminalLines: scanTerminalLines,
                    cursorColor: scanCursorColor,
                    scanProgressFraction: scanProgressFraction
                )
                .scaleEffect(isDeepDiving ? 2.5 : 1)
                .opacity(isDeepDiving ? 0 : 1)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.6), value: isDeepDiving)
            } else if isDragTargeted {
                WelcomeDropOverlayView()
            }

            if whiteFlash {
                Color.white.ignoresSafeArea()
                    .opacity(whiteFlash ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: whiteFlash)
            }
        }
        .scaleEffect(isDeepDiving ? 12.0 : 1.0)
        .animation(.timingCurve(0.7, 0, 1, 1, duration: 0.6), value: isDeepDiving)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDragTargeted
        ) { _ in
            startScanningSequence()
            return true
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            titlebar

            Spacer()

            WelcomeStageSwitcher(stage: displayStage, parallax: mouseParallax)
                .frame(height: 340)
                .padding(.horizontal, 60)

            featuresGrid
                .frame(height: 140)
                .padding(.horizontal, 40)
                .padding(.top, 12)

            Spacer()

            footer
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var windowBorderColor: Color {
        let accent = accentForStage(displayStage)
        return AreaMatrixTheme.Surfaces.windowBorder(accent: accent, colorScheme: colorScheme)
    }

    private func accentForStage(_ stage: WelcomeStage) -> Color {
        switch stage {
        case .default: AreaMatrixTheme.Colors.teal
        case .feat1: AreaMatrixTheme.Colors.tealBright
        case .feat2: AreaMatrixTheme.Colors.gold
        case .feat3: AreaMatrixTheme.Colors.coral
        case .feat4: AreaMatrixTheme.Colors.purple
        case .feat5: AreaMatrixTheme.Colors.emerald
        }
    }
}

private extension WelcomeStepView {
    private var titlebar: some View {
        ZStack {
            HStack(spacing: 0) {
                Text("AreaMatrix")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                AreaMatrixThemeToggleButton(themeOverride: $themeOverride)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
    }

    private var featuresGrid: some View {
        HStack(spacing: 20) {
            featureCard(WelcomeFeatureCardSpec(
                icon: "arrow.down.doc",
                title: "拖拽归档，智能分类",
                description: "识别、重命名并自动落位",
                accentColor: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255),
                stage: .feat1,
                entranceDelay: 0.3
            ))
            featureCard(WelcomeFeatureCardSpec(
                icon: "checkmark.shield",
                title: "零侵入，绝对安全",
                description: "不碰原文件，真相在文件系统",
                accentColor: Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255),
                stage: .feat2,
                entranceDelay: 0.55
            ))
            featureCard(WelcomeFeatureCardSpec(
                icon: "rectangle.split.2x1",
                title: "全局概览，改动追溯",
                description: "生成大纲，双向同步改动日志",
                accentColor: Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255),
                stage: .feat3,
                entranceDelay: 0.8
            ))
        }
    }

    private var footer: some View {
        HStack {
            Button(
                action: onLearnMore,
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                        Text("了解 AreaMatrix 如何工作")
                            .background(
                                Rectangle()
                                    .frame(height: 1)
                                    .offset(y: 2)
                                    .opacity(isLearnMoreHovered ? 1 : 0),
                                alignment: .bottom
                            )
                        ZStack {
                            Image(systemName: "arrow.up.right")
                                .opacity(isLearnMoreHovered ? 0 : 0.6)
                                .offset(x: isLearnMoreHovered ? 10 : 0, y: isLearnMoreHovered ? -10 : 0)
                            Image(systemName: "arrow.up.right")
                                .opacity(isLearnMoreHovered ? 0.6 : 0)
                                .offset(x: isLearnMoreHovered ? 0 : -10, y: isLearnMoreHovered ? 10 : 0)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12, height: 12)
                        .clipped()
                    }
                    .font(.system(size: 13))
                    .foregroundColor(isLearnMoreHovered ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(isLearnMoreHovered ? 0.06 : 0))
                    )
                    .animation(.easeOut(duration: 0.2), value: isLearnMoreHovered)
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(.plain)
            .focused($isLearnMoreFocused)
            .focusEffectDisabled()
            .onChange(of: isLearnMoreFocused) { _, focused in
                if focused {
                    activateHoverStage(.feat4)
                } else if hoverStage == .feat4 {
                    scheduleHoverReset(for: .feat4)
                }
            }
            .onHover { hovering in
                isLearnMoreHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                    activateHoverStage(.feat4)
                } else {
                    NSCursor.pop()
                    scheduleHoverReset(for: .feat4)
                }
            }
            .opacity(footerEntered ? 1 : 0)
            .offset(y: footerEntered ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.5), value: footerEntered)

            Spacer()

            Button(
                action: {
                    startScanningSequence()
                },
                label: {
                    AreaMatrixPrimaryGlowButton(
                        accent: AreaMatrixTheme.Colors.teal,
                        isHovered: isCtaHovered,
                        shimmerPhase: $shimmerPhase
                    ) {
                        HStack(spacing: 6) {
                            Text("选择本地文件夹")
                            Color.clear
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Image(systemName: "folder.badge.plus")
                                        .symbolEffect(.bounce, value: isCtaHovered)
                                )
                            Text("⌘O")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .padding(.leading, 4)
                        }
                    }
                }
            )
            .buttonStyle(.plain)
            .focused($isChooseFolderFocused)
            .focusEffectDisabled()
            .onChange(of: isChooseFolderFocused) { _, focused in
                if focused {
                    activateHoverStage(.feat5)
                } else if hoverStage == .feat5 {
                    scheduleHoverReset(for: .feat5)
                }
            }
            .onHover { hovering in
                isCtaHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                    activateHoverStage(.feat5)
                } else {
                    NSCursor.pop()
                    scheduleHoverReset(for: .feat5)
                }
            }
            .opacity(footerEntered ? 1 : 0)
            .offset(y: footerEntered ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.6), value: footerEntered)
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
    }

    private func featureCard(_ spec: WelcomeFeatureCardSpec) -> some View {
        let isHovered = hoverStage == spec.stage

        return WelcomeFeatureCard(
            icon: spec.icon,
            title: spec.title,
            description: spec.description,
            accentColor: spec.accentColor,
            isHovered: isHovered,
            entranceDelay: spec.entranceDelay,
            anyCardHovered: hoverStage != nil && [WelcomeStage.feat1, .feat2, .feat3].contains(hoverStage!),
            onHoverChanged: { hovering in
                if hovering {
                    activateHoverStage(spec.stage)
                } else if hoverStage == spec.stage {
                    scheduleHoverReset(for: spec.stage)
                }
            }
        )
    }

    private func activateHoverStage(_ stage: WelcomeStage) {
        hoverResetTask?.cancel()
        guard hoverStage != stage else { return }
        hoverStage = stage
    }

    private func scheduleHoverReset(for stage: WelcomeStage) {
        hoverResetTask?.cancel()
        hoverResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, hoverStage == stage else { return }
            hoverStage = nil
        }
    }

    private func navigateStage(direction: Int, wrap: Bool = false) {
        let stages = WelcomeStage.allCases
        let current = stages.firstIndex(of: activeStage) ?? 0
        let next: Int = if wrap {
            (current + direction + stages.count) % stages.count
        } else {
            max(0, min(stages.count - 1, current + direction))
        }
        guard stages[next] != activeStage else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)) {
            activeStage = stages[next]
        }
    }

    private func updateParallax(from phase: HoverPhase, in size: CGSize) {
        switch phase {
        case let .active(location):
            let width = max(size.width, 1)
            let height = max(size.height, 1)
            let next = WelcomeParallax(
                horizontal: ((location.x / width) - 0.5) * 2,
                vertical: ((location.y / height) - 0.5) * 2
            )
            mouseParallax = next
        case .ended:
            mouseParallax = .zero
        }
    }

    private func startScanningSequence() {
        guard !isScanning else { return }
        scanTask?.cancel()
        scanTerminalLines = []
        scanCursorColor = AreaMatrixTheme.Colors.tealBright
        scanProgressFraction = 0
        withAnimation { isScanning = true }

        scanTask = Task { @MainActor in
            let logs = [
                ("初始化 AreaMatrix 核心引擎...", AreaMatrixTheme.Colors.tealBright),
                ("扫描文件指纹并生成索引...", AreaMatrixTheme.Colors.tealBright),
                ("建立 AREAMATRIX.md 概览映射...", AreaMatrixTheme.Colors.teal),
                ("接管完毕，安全网罩已启动。", AreaMatrixTheme.Colors.gold)
            ]

            for (index, log) in logs.enumerated() {
                guard await typeScanLog(log.0, color: log.1) else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    scanProgressFraction = CGFloat(index + 1) / 5.0
                }
                try? await Task.sleep(for: .milliseconds(240))
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard await typeScanLog(">>> 授权通过，正在进入 <<<", color: AreaMatrixTheme.Colors.gold) else { return }
            withAnimation(.easeOut(duration: 0.3)) { scanProgressFraction = 1.0 }

            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }

            withAnimation(.timingCurve(0.7, 0, 1, 1, duration: 0.6)) { isDeepDiving = true }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.15)) { whiteFlash = true }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            onContinue()
            isScanning = false
            isDeepDiving = false
            whiteFlash = false
            scanProgressFraction = 0
        }
    }

    private func typeScanLog(_ text: String, color: Color) async -> Bool {
        let line = WelcomeTerminalLine(text: "", color: color)
        scanCursorColor = color
        withAnimation(.easeOut(duration: 0.25)) {
            scanTerminalLines.append(line)
            if scanTerminalLines.count > 5 {
                scanTerminalLines.removeFirst()
            }
        }

        for character in text {
            try? await Task.sleep(for: .milliseconds(18))
            guard !Task.isCancelled else { return false }
            if let index = scanTerminalLines.firstIndex(where: { $0.id == line.id }) {
                scanTerminalLines[index].text.append(character)
            }
        }

        return true
    }
}
