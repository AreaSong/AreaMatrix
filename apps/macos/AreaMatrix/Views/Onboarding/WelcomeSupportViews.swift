import AppKit
import SwiftUI

struct WelcomeTerminalLine: Identifiable {
    let id = UUID()
    var text: String
    let color: Color
}

struct WelcomeTrafficLights: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            trafficLight(color: Color(red: 1, green: 0.373, blue: 0.337), symbol: "xmark")
            trafficLight(color: Color(red: 1, green: 0.741, blue: 0.18), symbol: "minus")
            trafficLight(color: Color(red: 0.153, green: 0.788, blue: 0.247), symbol: "plus")
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private func trafficLight(color: Color, symbol: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.black.opacity(0.52))
                    .opacity(isHovered ? 1 : 0)
            )
    }
}

struct WelcomeFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let isHovered: Bool
    let entranceDelay: Double
    let anyCardHovered: Bool
    let onHoverChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var hasEntered = false
    @State private var hoverPoint = UnitPoint.center
    @FocusState private var isFocused: Bool
    @State private var idleGlarePhase: CGFloat = -0.5

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Stable Hit Area (Does not move or scale)
                Color.clear
                    .contentShape(Rectangle())
                    .focusable(true)
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .onChange(of: isFocused) { _, focused in
                        if focused {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        }
                        onHoverChanged(focused)
                    }
                    .onContinuousHover { phase in
                        updateHover(phase: phase, in: proxy.size)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Color.clear
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .medium))
                                .symbolEffect(.bounce, value: isHovered)
                                .foregroundColor(isHovered ? .white : accentColor)
                        )
                        .background(isHovered ? accentColor : Color.primary.opacity(0.05))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .shadow(color: isHovered ? accentColor.opacity(0.5) : .clear, radius: 16, y: 4)
                        .padding(.bottom, 8)

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.ultraThinMaterial)
                .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(cardSpotlight)
                .overlay(cardBorder)
                .overlay(cardTopAccent, alignment: .top)
                .overlay(cardGlare)
                .overlay(cardIdleGlare)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.05), radius: isHovered ? 24 : 10, y: isHovered ? 12 : 4)
                .offset(y: hasEntered ? 0 : 16)
                .opacity(hasEntered ? 1 : 0)
                .rotation3DEffect(
                    .degrees(hasEntered ? 0 : 5),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.5
                )
                .featureCardFocus(isHovered: isHovered, anyCardHovered: anyCardHovered)
                .animation(.easeOut(duration: 0.15), value: hoverPoint)
                .allowsHitTesting(false)
                .animation(.areaMatrixStageFlow.delay(entranceDelay), value: hasEntered)
            }
            .onAppear {
                hasEntered = true
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false).delay(6.0 + entranceDelay)) {
                    idleGlarePhase = 1.5
                }
            }
        }
    }

    private var cardSpotlight: some View {
        RadialGradient(
            colors: [
                Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.08 : 0.05) : 0),
                .clear
            ],
            center: hoverPoint,
            startRadius: 0,
            endRadius: 180
        )
        .blendMode(colorScheme == .dark ? .screen : .normal)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cardIdleGlare: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(colorScheme == .dark ? 0.35 : 0.7), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: 250)
        .offset(x: (idleGlarePhase * 800) - 400)
        .mask(RoundedRectangle(cornerRadius: 8))
        .opacity(isHovered ? 0 : 1) // 悬停时不播放闲置反光
        .allowsHitTesting(false)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                LinearGradient(
                    colors: [
                        isHovered ? Color.primary.opacity(0.3) : Color.primary.opacity(0.1),
                        Color.primary.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var cardTopAccent: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(accentColor)
                .frame(width: isHovered ? geo.size.width : 40, height: 3)
                .frame(maxWidth: .infinity)
                .shadow(color: isHovered ? accentColor.opacity(0.8) : .clear, radius: 12)
        }
        .frame(height: 3)
        .opacity(isHovered ? 1 : 0.5)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isHovered)
    }

    private var cardGlare: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            LinearGradient(
                colors: [.clear, Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: w * 2, height: h * 2)
            .rotationEffect(.degrees(-20))
            .offset(
                x: (hoverPoint.x - 0.5) * w * 1.5,
                y: (hoverPoint.y - 0.5) * h * 1.5
            )
            .opacity(isHovered ? 1 : 0)
            .blendMode(colorScheme == .dark ? .plusLighter : .screen)
        }
        .allowsHitTesting(false)
    }

    private func updateHover(phase: HoverPhase, in size: CGSize) {
        switch phase {
        case let .active(location):
            hoverPoint = UnitPoint(
                x: max(0, min(1, location.x / max(size.width, 1))),
                y: max(0, min(1, location.y / max(size.height, 1)))
            )
            if !isHovered {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                onHoverChanged(true)
            }
        case .ended:
            if isHovered {
                hoverPoint = .center
                onHoverChanged(false)
            }
        }
    }
}

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

struct WelcomeHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        for index in 0 ..< 6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

/// 文件夹图标形状 — tab 与主体一体化绘制，消除描边断裂
struct WelcomeFolderShape: Shape {
    let tabWidth: CGFloat
    let tabHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, tabWidth / 2, tabHeight / 2)
        let br = cornerRadius
        var p = Path()

        // 从 tab 左上角开始，顺时针绘制
        p.move(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: tabWidth - r, y: 0))
        p.addArc(center: CGPoint(x: tabWidth - r, y: r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: tabWidth, y: tabHeight))
        p.addLine(to: CGPoint(x: rect.width - br, y: tabHeight))
        p.addArc(center: CGPoint(x: rect.width - br, y: tabHeight + br), radius: br,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - br))
        p.addArc(center: CGPoint(x: rect.width - br, y: rect.height - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: br, y: rect.height))
        p.addArc(center: CGPoint(x: br, y: rect.height - br), radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()

        return p
    }
}

struct WelcomeWindowChromeObserver: NSViewRepresentable {
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
        private var previousIsOpaque: Bool?
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
                previousIsOpaque = window.isOpaque
                previousBackgroundColor = window.backgroundColor
                previousStyleMask = window.styleMask
            }

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isOpaque = false
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
            if let previousIsOpaque {
                window.isOpaque = previousIsOpaque
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

// MARK: - Core Animation Curves
extension Animation {
    /// 匹配 HTML 原型里的 cubic-bezier(0.16, 1, 0.3, 1)
    static var areaMatrixSpring: Animation {
        .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)
    }
    
    /// 用于卡片 Hover 等微交互的弹性动画
    static var areaMatrixHover: Animation {
        .spring(response: 0.3, dampingFraction: 0.6)
    }
    
    static var areaMatrixStageFlow: Animation {
        .spring(response: 0.6, dampingFraction: 0.82)
    }
}

// MARK: - Stage Transition
extension AnyTransition {
    /// HTML 原型的 Stage 转场：
    /// Active: translateY(0) scale(1)
    /// Exit: translateY(-16px) scale(0.98)
    /// Enter: translateY(20px) scale(0.96)
    static var areaMatrixStage: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: StageTransitionModifier(opacity: 0, yOffset: 20, scale: 0.96),
                identity: StageTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            ),
            removal: .modifier(
                active: StageTransitionModifier(opacity: 0, yOffset: -16, scale: 0.98),
                identity: StageTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            )
        )
    }
}

private struct StageTransitionModifier: ViewModifier {
    let opacity: Double
    let yOffset: CGFloat
    let scale: CGFloat
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: yOffset)
    }
}

// MARK: - Feature Card Hover Modifier
struct FeatureCardFocusModifier: ViewModifier {
    let isHovered: Bool
    let anyCardHovered: Bool
    
    func body(content: Content) -> some View {
        content
            // Focus Dimming：非 hover 卡片淡出和脱色
            .opacity(anyCardHovered ? (isHovered ? 1.0 : 0.4) : 1.0)
            .saturation(anyCardHovered ? (isHovered ? 1.0 : 0.4) : 1.0)
            .animation(.areaMatrixHover, value: isHovered)
            .animation(.easeOut(duration: 0.4), value: anyCardHovered)
    }
}

public extension View {
    func featureCardFocus(isHovered: Bool, anyCardHovered: Bool) -> some View {
        modifier(FeatureCardFocusModifier(isHovered: isHovered, anyCardHovered: anyCardHovered))
    }
}

// MARK: - Text Shimmer Modifier
struct TextShimmerModifier: ViewModifier {
    @State private var shimmerOffset: CGFloat = -1.0
    let primaryColor: Color
    let highlightColor: Color
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: primaryColor, location: shimmerOffset),
                        .init(color: highlightColor, location: shimmerOffset + 0.5),
                        .init(color: primaryColor, location: shimmerOffset + 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.0
                }
            }
    }
}

public extension View {
    func textShimmer(primary: Color = .primary, highlight: Color, duration: Double = 4.0) -> some View {
        modifier(TextShimmerModifier(primaryColor: primary, highlightColor: highlight, duration: duration))
    }
}

// MARK: - Pulse Aura Modifier
struct PulseAuraModifier: ViewModifier {
    @State private var isAnimating = false
    let color: Color
    let duration: Double
    let maxScale: CGFloat
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 扩散光环 1
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(color.opacity(0.6), lineWidth: 2)
                        .scaleEffect(isAnimating ? maxScale : 0.9)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeOut(duration: duration).repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                    
                    // 扩散光环 2（延迟）
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                        .scaleEffect(isAnimating ? maxScale : 0.9)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeOut(duration: duration).repeatForever(autoreverses: false).delay(duration * 0.4),
                            value: isAnimating
                        )
                }
            )
            .onAppear {
                isAnimating = true
            }
    }
}

public extension View {
    func pulseAura(color: Color, duration: Double = 2.5, maxScale: CGFloat = 1.7, cornerRadius: CGFloat = 28) -> some View {
        modifier(PulseAuraModifier(color: color, duration: duration, maxScale: maxScale, cornerRadius: cornerRadius))
    }
}

// MARK: - Magnetic Hover Modifier
struct MagneticHoverModifier: ViewModifier {
    @State private var offset: CGSize = .zero
    let intensity: CGFloat
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset.width, y: offset.height)
            .animation(.interpolatingSpring(stiffness: 150, damping: 12), value: offset)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                                let dx = (location.x - center.x) * intensity
                                let dy = (location.y - center.y) * intensity
                                offset = CGSize(width: dx, height: dy)
                            case .ended:
                                offset = .zero
                            }
                        }
                }
            )
    }
}

public extension View {
    func magneticHover(intensity: CGFloat = 0.2) -> some View {
        modifier(MagneticHoverModifier(intensity: intensity))
    }
}

// MARK: - Matrix Decode Text Effect

public struct MatrixText: View {
    public let text: String
    public var gradient: LinearGradient?
    
    @State private var displayText: String = ""
    @State private var timerTask: Task<Void, Never>?
    
    private let asciiChars = Array("!@#$%^&*()_+-=[]{}|;:',.<>?/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    
    public init(text: String, gradient: LinearGradient? = nil) {
        self.text = text
        self.gradient = gradient
    }
    
    public var body: some View {
        Group {
            if let gradient = gradient {
                Text(displayText)
                    .foregroundStyle(gradient)
            } else {
                Text(displayText)
            }
        }
        .onAppear { startDecode() }
        .onChange(of: text) { _, _ in startDecode() }
    }
    
    private func startDecode() {
        timerTask?.cancel()
        displayText = text // 初始值（在第一帧渲染前）
        
        timerTask = Task { @MainActor in
            let targetArray = Array(text)
            var currentArray = Array(repeating: Character(" "), count: targetArray.count)
            
            for i in 0..<targetArray.count {
                // 闪烁 2 次乱码
                for _ in 0..<2 {
                    try? await Task.sleep(for: .milliseconds(12))
                    guard !Task.isCancelled else { return }
                    
                    for j in i..<targetArray.count {
                        if targetArray[j].isWhitespace {
                            currentArray[j] = " "
                        } else {
                            currentArray[j] = asciiChars.randomElement()!
                        }
                    }
                    displayText = String(currentArray)
                }
                
                // 定格真实字符
                currentArray[i] = targetArray[i]
                displayText = String(currentArray)
            }
            await MainActor.run {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}
