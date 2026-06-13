import AppKit
import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeStage: WelcomeStage = .default
    @State private var hoverStage: WelcomeStage?
    @State private var isScanning = false
    @State private var ctaGlowing = false
    /// 用户手动切换的主题偏好：nil = 跟随系统
    @State private var themeOverride: ColorScheme?

    /// Derived stage to show
    private var displayStage: WelcomeStage {
        hoverStage ?? activeStage
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ZStack {
                WelcomeAmbientBackground(stage: displayStage)

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
                    .clipped()

                    featuresGrid
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)

                    footer
                }
            }
            .frame(width: 860, height: 640)
            .background(windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(windowBorderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.8 : 0.18), radius: 60, y: 30)
            .blur(radius: isScanning ? 12 : 0)
            .scaleEffect(isScanning ? 0.92 : 1)
            .opacity(isScanning ? 0.05 : 1)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isScanning)

            // Scanning Overlay
            if isScanning {
                scanOverlay
            }
        }
        .frame(width: 860, height: 640)
        .background(WelcomeWindowChromeObserver())
        .preferredColorScheme(themeOverride)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                ctaGlowing = true
            }
        }
    }

    private var windowBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 13 / 255, green: 40 / 255, blue: 35 / 255),
                    Color(red: 7 / 255, green: 21 / 255, blue: 19 / 255),
                ]
                : [
                    Color.white,
                    Color(red: 242 / 255, green: 247 / 255, blue: 245 / 255),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var windowBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

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
                    withAnimation { isScanning = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        onContinue()
                        isScanning = false
                    }
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

    private var scanOverlay: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 8]))
                    .frame(width: 160, height: 160)
                    .foregroundColor(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isScanning)

                Image(colorScheme == .dark ? "AreaMatrixLogoMarkDark" : "AreaMatrixLogoMarkLight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255).opacity(0.5), radius: 10)
            }

            Text("等待系统指令...")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                .shadow(color: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255).opacity(0.4), radius: 8)
        }
        .scaleEffect(isScanning ? 1 : 0.9)
        .opacity(isScanning ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: isScanning)
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
}

private struct WelcomeFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let isHovered: Bool
    let dimmingOpacity: Double
    let dimmingSaturation: Double
    let onHoverChanged: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isHovered ? .white : accentColor)
                .frame(width: 36, height: 36)
                .background(isHovered ? accentColor : Color.primary.opacity(0.05))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .shadow(color: isHovered ? accentColor.opacity(0.5) : .clear, radius: 8, y: 4)
                .padding(.bottom, 4)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .overlay(
            Rectangle()
                .fill(accentColor)
                .frame(height: 3)
                .opacity(isHovered ? 1 : 0.5),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0), radius: 16, y: 8)
        .scaleEffect(isHovered ? 1.02 : 1)
        .opacity(dimmingOpacity)
        .saturation(dimmingSaturation)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .animation(.easeOut(duration: 0.4), value: dimmingOpacity)
        .onHover(perform: onHoverChanged)
        .onTapGesture(perform: onTap)
    }
}

/// Helper for bottom corners
struct CustomBottomCorners: Shape {
    var radius: CGFloat = .infinity
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addArc(
            center: CGPoint(x: rect.width - radius, y: rect.height - radius),
            radius: radius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addArc(
            center: CGPoint(x: radius, y: rect.height - radius),
            radius: radius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: 0))
        return path
    }
}

private struct WelcomeWindowChromeObserver: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.configure(window: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.configure(window: nsView.window) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.restore(window: nsView.window)
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?
        private var previousTitleVisibility: NSWindow.TitleVisibility?
        private var previousTitlebarAppearsTransparent: Bool?
        private var previousIsMovableByWindowBackground: Bool?
        private var previousBackgroundColor: NSColor?
        private var previousStyleMask: NSWindow.StyleMask?

        func configure(window: NSWindow?) {
            guard let window else { return }
            if configuredWindow !== window {
                restore(window: configuredWindow)
                configuredWindow = window
                previousTitleVisibility = window.titleVisibility
                previousTitlebarAppearsTransparent = window.titlebarAppearsTransparent
                previousIsMovableByWindowBackground = window.isMovableByWindowBackground
                previousBackgroundColor = window.backgroundColor
                previousStyleMask = window.styleMask
            }

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
        }

        func restore(window: NSWindow?) {
            guard let window,
                  configuredWindow === window else { return }
            if let previousTitleVisibility {
                window.titleVisibility = previousTitleVisibility
            }
            if let previousTitlebarAppearsTransparent {
                window.titlebarAppearsTransparent = previousTitlebarAppearsTransparent
            }
            if let previousIsMovableByWindowBackground {
                window.isMovableByWindowBackground = previousIsMovableByWindowBackground
            }
            if let previousBackgroundColor {
                window.backgroundColor = previousBackgroundColor
            }
            if let previousStyleMask {
                window.styleMask = previousStyleMask
            }
        }
    }
}
