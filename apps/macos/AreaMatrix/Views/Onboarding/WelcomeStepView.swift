import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum WelcomeWindowMetrics {
    static let width: CGFloat = 860
    static let height: CGFloat = 640
    static let cornerRadius: CGFloat = 12
}

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeStage: WelcomeStage = .default
    @State private var hoverStage: WelcomeStage?
    @State private var isScanning = false
    @State private var isDeepDiving = false
    @State private var whiteFlash = false
    @State private var isDragTargeted = false
    @State private var isCtaHovered = false
    @State private var isLearnMoreHovered = false
    @State private var footerEntered = false

    static var hasPlayedLaunchAnimation = false
    @State private var mouseParallax = AreaMatrixParallax.zero
    @State private var scanTerminalLines = [
        AreaMatrixTerminalLine(text: "等待系统指令...", colorToken: AreaMatrixTheme.Colors.tealText)
    ]
    @State private var scanCursorColorToken = AreaMatrixTheme.Colors.tealText
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
            AreaMatrixAmbientBackground(scene: displayStage.ambientScene, parallax: mouseParallax)
                .blur(radius: isScanning ? 16 : 0)
                .animation(.areaMatrixOverlayFade, value: isScanning)

            welcomeContent
                .areaMatrixScanningContent(isScanning: isScanning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WelcomeWindowMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WelcomeWindowMetrics.cornerRadius, style: .continuous)
                .stroke(windowBorderColor, lineWidth: 1)
                .animation(.areaMatrixOverlayFade, value: displayStage)
        )
        .shadow(
            color: isDeepDiving ? .clear : AreaMatrixTheme.Surfaces.windowShadow(colorScheme: colorScheme),
            radius: isDeepDiving ? 0 : 60,
            x: mouseParallax.horizontal * -10,
            y: mouseParallax.vertical * -10 + 30
        )
        .ignoresSafeArea(.container, edges: .all)
        .overlay {
            if isScanning {
                AreaMatrixScanOverlay(
                    isScanning: isScanning,
                    terminalLines: scanTerminalLines,
                    cursorColorToken: scanCursorColorToken,
                    progressFraction: scanProgressFraction,
                    accent: displayStage.accentColor
                )
                .opacity(isDeepDiving ? 0 : 1)
                .areaMatrixDeepDive(isActive: isDeepDiving, scale: 2.5)
            } else if isDragTargeted {
                AreaMatrixDropOverlay()
            }

            if whiteFlash {
                AreaMatrixWhiteFlashOverlay(isVisible: whiteFlash)
            }
        }
        .compositingGroup()
        .areaMatrixDeepDive(isActive: isDeepDiving, scale: 1.05)
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
        let accent = displayStage.accentColor
        return AreaMatrixTheme.Surfaces.windowBorder(accent: accent, colorScheme: colorScheme)
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
        AreaMatrixFeatureCardGroup(
            cards: featureCards,
            activeID: hoverStage,
            onHoverChanged: { stage, hovering in
                if hovering {
                    activateHoverStage(stage)
                } else if hoverStage == stage {
                    scheduleHoverReset(for: stage)
                }
            }
        )
    }

    private var featureCards: [AreaMatrixFeatureCardSpec<WelcomeStage>] {
        [
            AreaMatrixFeatureCardSpec(
                id: .feat1,
                icon: "arrow.down.doc",
                title: "拖拽归档，智能分类",
                description: "识别、重命名并自动落位",
                accentColor: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255),
                entranceDelay: 0.3
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat2,
                icon: "checkmark.shield",
                title: "零侵入，绝对安全",
                description: "不碰原文件，真相在文件系统",
                accentColor: Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255),
                entranceDelay: 0.55
            ),
            AreaMatrixFeatureCardSpec(
                id: .feat3,
                icon: "rectangle.split.2x1",
                title: "全局概览，改动追溯",
                description: "生成大纲，双向同步改动日志",
                accentColor: Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255),
                entranceDelay: 0.8
            )
        ]
    }

    private var footer: some View {
        HStack {
            Button(
                action: onLearnMore,
                label: {
                    AreaMatrixLinkActionLabel(
                        title: "了解 AreaMatrix 如何工作",
                        iconName: "questionmark.circle",
                        isHovered: isLearnMoreHovered
                    )
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
            .areaMatrixDelayedEntrance(isVisible: footerEntered, delay: 0.5)

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
                        AreaMatrixPrimaryActionLabel(
                            title: "选择本地文件夹",
                            iconName: "folder.badge.plus",
                            shortcut: "⌘O",
                            isHovered: isCtaHovered
                        )
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
            .areaMatrixDelayedEntrance(isVisible: footerEntered, delay: 0.6)
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
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
        withAnimation(.areaMatrixStageEnterExit) {
            activeStage = stages[next]
        }
    }

    private func startScanningSequence() {
        guard !isScanning else { return }
        scanTask?.cancel()
        scanTerminalLines = []
        scanCursorColorToken = AreaMatrixTheme.Colors.tealText
        scanProgressFraction = 0
        withAnimation { isScanning = true }

        scanTask = Task { @MainActor in
            let logs = [
                ("初始化 AreaMatrix 核心引擎...", AreaMatrixTheme.Colors.tealText),
                ("扫描文件指纹并生成索引...", AreaMatrixTheme.Colors.tealText),
                ("建立 AREAMATRIX.md 概览映射...", AreaMatrixTheme.Colors.tealText),
                ("接管完毕，安全网罩已启动。", AreaMatrixTheme.Colors.goldText)
            ]
            let stages: [WelcomeStage] = [.feat1, .feat2, .feat3, .feat4]

            for (index, log) in logs.enumerated() {
                guard await typeScanLog(log.0, colorToken: log.1) else { return }
                withAnimation(.areaMatrixProgressStep) {
                    scanProgressFraction = CGFloat(index + 1) / 5.0
                    activeStage = stages[index]
                }
                try? await Task.sleep(for: .milliseconds(240))
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard await typeScanLog(">>> 授权通过，正在进入 <<<", colorToken: AreaMatrixTheme.Colors.goldText) else { return }
            withAnimation(.areaMatrixProgressStep) {
                scanProgressFraction = 1.0
                activeStage = .feat5
            }

            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }

            withAnimation(.areaMatrixDeepDive) { isDeepDiving = true }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            withAnimation(.areaMatrixFlashIn) { whiteFlash = true }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            onContinue()
            isScanning = false
            isDeepDiving = false
            whiteFlash = false
            scanProgressFraction = 0
        }
    }

    private func typeScanLog(_ text: String, colorToken: AreaMatrixColorToken) async -> Bool {
        let line = AreaMatrixTerminalLine(text: "", colorToken: colorToken)
        scanCursorColorToken = colorToken
        scanTerminalLines.appendTerminalLine(line)
        return await AreaMatrixTerminalLogTypewriter.type(text) { character in
            scanTerminalLines.appendTerminalCharacter(character, toLineWithID: line.id)
        }
    }
}
