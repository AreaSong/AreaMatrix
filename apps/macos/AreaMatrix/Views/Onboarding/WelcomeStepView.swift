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
    @State private var isDragTargeted = false
    @State private var hasLaunched = false
    @State private var ctaGlowing = false
    @State private var mouseParallax = WelcomeParallax.zero
    @State private var scanTerminalLines = [
        WelcomeTerminalLine(text: "等待系统指令...", color: WelcomePalette.tealBright)
    ]
    @State private var scanCursorColor = WelcomePalette.tealBright
    @State private var scanTask: Task<Void, Never>?
    /// 用户手动切换的主题偏好：nil = 跟随系统
    @State private var themeOverride: ColorScheme?

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
            .background(WelcomeWindowChromeObserver())
            .preferredColorScheme(themeOverride)
            .scaleEffect(hasLaunched ? 1 : 0.95)
            .offset(y: hasLaunched ? 0 : 20)
            .opacity(hasLaunched ? 1 : 0)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8), value: hasLaunched)
            .onAppear {
                hasLaunched = true
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    ctaGlowing = true
                }
            }
            .onDisappear {
                scanTask?.cancel()
            }
    }

    private var welcomeSurface: some View {
        GeometryReader { proxy in
            ZStack {
                WelcomeAmbientBackground(stage: displayStage, parallax: mouseParallax)

                welcomeContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onContinuousHover { phase in
                updateParallax(from: phase, in: proxy.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WelcomeWindowMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WelcomeWindowMetrics.cornerRadius, style: .continuous)
                .stroke(windowBorderColor, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.8 : 0.18),
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
                    cursorColor: scanCursorColor
                )
            } else if isDragTargeted {
                WelcomeDropOverlayView()
            }
        }
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

            ZStack {
                switch displayStage {
                case .default: StageDefaultView().transition(stageTransition)
                case .feat1: StageClassifyView().transition(stageTransition)
                case .feat2: StageSecurityView().transition(stageTransition)
                case .feat3: StageTrackingView().transition(stageTransition)
                case .feat4: StageHelpView().transition(stageTransition)
                case .feat5: StageStartView().transition(stageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 60)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .rotation3DEffect(
                .degrees(mouseParallax.vertical * -4),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.7
            )
            .rotation3DEffect(
                .degrees(mouseParallax.horizontal * 4),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.7
            )
            .clipped()

            featuresGrid
                .padding(.horizontal, 40)
                .padding(.bottom, 20)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var windowBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}

private extension WelcomeStepView {
    private var titlebar: some View {
        ZStack {
            Text("AreaMatrix")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if themeOverride == nil {
                            // 首次点击：切换到当前的反面
                            themeOverride = colorScheme == .dark ? .light : .dark
                        } else {
                            themeOverride = themeOverride == .dark ? .light : .dark
                        }
                    }
                } label: {
                    Image(systemName: (themeOverride ?? colorScheme) == .dark ? "sun.max" : "moon")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48)
    }

    private var stageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var featuresGrid: some View {
        HStack(spacing: 20) {
            featureCard(
                icon: "arrow.down.doc",
                title: "拖拽归档，智能分类",
                description: "识别、重命名并自动落位",
                accentColor: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255),
                stage: .feat1
            )
            featureCard(
                icon: "checkmark.shield",
                title: "零侵入，绝对安全",
                description: "不碰原文件，真相在文件系统",
                accentColor: Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255),
                stage: .feat2
            )
            featureCard(
                icon: "rectangle.split.2x1",
                title: "全局概览，改动追溯",
                description: "生成大纲，双向同步改动日志",
                accentColor: Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255),
                stage: .feat3
            )
        }
        .frame(height: 128)
    }

    /// 当有卡片被 hover 时，其他卡片降低不透明度（匹配 HTML opacity: 0.4）
    private func focusDimmingOpacity(for stage: WelcomeStage) -> Double {
        guard let hover = hoverStage,
              [WelcomeStage.feat1, .feat2, .feat3].contains(hover) else { return 1 }
        return hover == stage ? 1 : 0.4
    }

    /// 非 hover 卡片添加灰度（匹配 HTML filter: grayscale(60%)）
    private func focusDimmingSaturation(for stage: WelcomeStage) -> Double {
        guard let hover = hoverStage,
              [WelcomeStage.feat1, .feat2, .feat3].contains(hover) else { return 1 }
        return hover == stage ? 1 : 0.4
    }

    private var footer: some View {
        HStack {
            Button(
                action: onLearnMore,
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                        Text("了解 AreaMatrix 如何工作")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation { hoverStage = hovering ? .feat4 : nil }
            }

            Spacer()

            Button(
                action: {
                    startScanningSequence()
                },
                label: {
                    HStack(spacing: 6) {
                        Text("选择本地文件夹")
                        Image(systemName: "folder.badge.plus")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [WelcomePalette.tealBright, WelcomePalette.teal],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(
                        color: WelcomePalette.teal.opacity(ctaGlowing ? 0.6 : 0.3),
                        radius: ctaGlowing ? 16 : 6,
                        y: 4
                    )
                }
            )
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation { hoverStage = hovering ? .feat5 : nil }
            }
        }
        .padding(.horizontal, 40)
        .frame(height: 60)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.02))
        .clipShape(CustomBottomCorners(radius: 12))
    }

    private func featureCard(
        icon: String,
        title: String,
        description: String,
        accentColor: Color,
        stage: WelcomeStage
    ) -> some View {
        let isHovered = hoverStage == stage

        return WelcomeFeatureCard(
            icon: icon,
            title: title,
            description: description,
            accentColor: accentColor,
            isHovered: isHovered,
            dimmingOpacity: focusDimmingOpacity(for: stage),
            dimmingSaturation: focusDimmingSaturation(for: stage),
            onHoverChanged: { hovering in
                if hovering {
                    withAnimation { hoverStage = stage }
                } else if hoverStage == stage {
                    withAnimation { hoverStage = nil }
                }
            },
            onTap: {
                withAnimation { activeStage = stage }
            }
        )
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
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)) {
                mouseParallax = next
            }
        case .ended:
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)) {
                mouseParallax = .zero
            }
        }
    }

    private func startScanningSequence() {
        guard !isScanning else { return }
        scanTask?.cancel()
        scanTerminalLines = []
        scanCursorColor = WelcomePalette.tealBright
        withAnimation { isScanning = true }

        scanTask = Task { @MainActor in
            let logs = [
                ("初始化 AreaMatrix 核心引擎...", WelcomePalette.tealBright),
                ("扫描文件指纹并生成索引...", WelcomePalette.tealBright),
                ("建立 AREAMATRIX.md 概览映射...", WelcomePalette.teal),
                ("接管完毕，安全网罩已启动。", WelcomePalette.gold)
            ]

            for log in logs {
                guard await typeScanLog(log.0, color: log.1) else { return }
                try? await Task.sleep(for: .milliseconds(240))
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard await typeScanLog(">>> 授权通过，正在进入 <<<", color: WelcomePalette.gold) else { return }

            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            onContinue()
            isScanning = false
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
