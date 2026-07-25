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
    @EnvironmentObject private var localizer: AppLocalizer
    @State private var activeScene: WelcomeScene = .default
    @State private var hoverScene: WelcomeScene?
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
        AreaMatrixTerminalLine(
            message: L10n.message("onboarding.welcome.terminal.waiting"),
            visibleCharacterCount: nil,
            colorToken: AreaMatrixTheme.Colors.tealText
        )
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

    /// Derived scene to show.
    private var displayScene: WelcomeScene {
        hoverScene ?? activeScene
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
                navigateScene(direction: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                navigateScene(direction: 1)
                return .handled
            }
    }

    private var welcomeSurface: some View {
        ZStack {
            AreaMatrixAmbientBackground(scene: displayScene.ambientScene, parallax: mouseParallax)
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
                .animation(.areaMatrixOverlayFade, value: displayScene)
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
                    accent: displayScene.accentColor
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

            WelcomeSceneSwitcher(scene: displayScene, parallax: mouseParallax)
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
        let accent = displayScene.accentColor
        return AreaMatrixTheme.Surfaces.windowBorder(accent: accent, colorScheme: colorScheme)
    }
}

private extension WelcomeStepView {
    private var titlebar: some View {
        WelcomeTitlebar(themeOverride: $themeOverride)
    }

    private var featuresGrid: some View {
        WelcomeFeatureCardsGrid(
            activeID: hoverScene,
            onHoverChanged: { scene, hovering in
                if hovering {
                    activateHoverScene(scene)
                } else if hoverScene == scene {
                    scheduleHoverReset(for: scene)
                }
            }
        )
    }

    private var footer: some View {
        HStack(alignment: .center) {
            AreaMatrixGhostButton(isHovered: isLearnMoreHovered, action: onLearnMore) {
                HStack(spacing: 8) {
                    AreaMatrixLucideIcon(name: .info, lineWidth: 2.0)
                        .frame(width: 14, height: 14)
                    Text(L10n.string("onboarding.welcome.learnMore").uppercased())
                }
            }
            .focused($isLearnMoreFocused)
            .focusEffectDisabled()
            .onChange(of: isLearnMoreFocused) { _, focused in
                if focused { activateHoverScene(.feat4) } else if hoverScene == .feat4 { scheduleHoverReset(for: .feat4) }
            }
            .onHover { hovering in
                isLearnMoreHovered = hovering
                AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
                if hovering { activateHoverScene(.feat4) } else { scheduleHoverReset(for: .feat4) }
            }
            .areaMatrixDelayedEntrance(isVisible: footerEntered, delay: AreaMatrixMotionTokens.EntranceDelay.footer)

            Spacer()

            AreaMatrixCapsuleButton(accent: AreaMatrixTheme.Colors.teal, isHovered: isCtaHovered, action: startScanningSequence) {
                HStack(spacing: 12) {
                    Text(L10n.string("onboarding.welcome.chooseFolder"))
                    AreaMatrixLucideIcon(name: .folder, lineWidth: 2.0)
                        .frame(width: 18, height: 18)
                        .offset(x: isCtaHovered ? 4 : 0)
                }
            }
            .keyboardShortcut("o", modifiers: [.command])
            .focused($isChooseFolderFocused)
            .focusEffectDisabled()
            .onChange(of: isChooseFolderFocused) { _, focused in
                if focused { activateHoverScene(.feat5) } else if hoverScene == .feat5 { scheduleHoverReset(for: .feat5) }
            }
            .onHover { hovering in
                isCtaHovered = hovering
                AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
                if hovering { activateHoverScene(.feat5) } else { scheduleHoverReset(for: .feat5) }
            }
            .areaMatrixDelayedEntrance(isVisible: footerEntered, delay: 0.6)
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
    }

    private func activateHoverScene(_ scene: WelcomeScene) {
        hoverResetTask?.cancel()
        guard hoverScene != scene else { return }
        hoverScene = scene
    }

    private func scheduleHoverReset(for scene: WelcomeScene) {
        hoverResetTask?.cancel()
        hoverResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, hoverScene == scene else { return }
            hoverScene = nil
        }
    }

    private func navigateScene(direction: Int, wrap: Bool = false) {
        let scenes = WelcomeScene.allCases
        let current = scenes.firstIndex(of: activeScene) ?? 0
        let next: Int = if wrap {
            (current + direction + scenes.count) % scenes.count
        } else {
            max(0, min(scenes.count - 1, current + direction))
        }
        guard scenes[next] != activeScene else { return }
        AppPlatformServices.interactionFeedback.performHaptic(.alignment)
        withAnimation(.areaMatrixSceneEnterExit) {
            activeScene = scenes[next]
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
                (L10n.message("onboarding.welcome.terminal.preparePicker"), AreaMatrixTheme.Colors.tealText),
                (L10n.message("onboarding.welcome.terminal.loadSafety"), AreaMatrixTheme.Colors.tealText),
                (L10n.message("onboarding.welcome.terminal.noWriteBeforeSelection"), AreaMatrixTheme.Colors.tealText),
                (L10n.message("onboarding.welcome.terminal.requestAccess"), AreaMatrixTheme.Colors.goldText)
            ]
            let scenes: [WelcomeScene] = [.feat1, .feat2, .feat3, .feat4]

            for (index, log) in logs.enumerated() {
                guard await typeScanLog(log.0, colorToken: log.1) else { return }
                withAnimation(.areaMatrixProgressStep) {
                    scanProgressFraction = CGFloat(index + 1) / 5.0
                    activeScene = scenes[index]
                }
                try? await Task.sleep(for: .milliseconds(240))
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard await typeScanLog(
                L10n.message("onboarding.welcome.terminal.openingPicker"),
                colorToken: AreaMatrixTheme.Colors.goldText
            ) else { return }
            withAnimation(.areaMatrixProgressStep) {
                scanProgressFraction = 1.0
                activeScene = .feat5
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

    private func typeScanLog(_ message: LocalizedMessage, colorToken: AreaMatrixColorToken) async -> Bool {
        let line = AreaMatrixTerminalLine(message: message, visibleCharacterCount: 0, colorToken: colorToken)
        scanCursorColorToken = colorToken
        scanTerminalLines.appendTerminalLine(line)
        let completed = await AreaMatrixTerminalLogTypewriter.type(
            localizer.resolve(message)
        ) { _ in
            scanTerminalLines.revealNextTerminalCharacter(toLineWithID: line.id)
        }
        if completed {
            scanTerminalLines.completeTerminalLine(withID: line.id)
        }
        return completed
    }
}
