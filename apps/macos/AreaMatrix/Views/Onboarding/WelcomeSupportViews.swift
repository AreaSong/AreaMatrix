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

    @State private var hasEntered = false
    @State private var hoverPoint = UnitPoint.center

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Stable Hit Area (Does not move or scale)
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        updateHover(phase: phase, in: proxy.size)
                    }

                // Visual Representation (Moves and scales)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isHovered ? .white : accentColor)
                        .frame(width: 40, height: 40)
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(cardBorder)
                .overlay(cardTopAccent, alignment: .top)
                .overlay(cardGlare)
                .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0), radius: 16, y: 8)
                .opacity(hasEntered ? 1 : 0)
                .featureCardFocus(isHovered: isHovered, anyCardHovered: anyCardHovered)
                .allowsHitTesting(false)
                .animation(.areaMatrixStageFlow.delay(entranceDelay), value: hasEntered)
            }
            .onAppear {
                hasEntered = true
            }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 1)
    }

    private var cardTopAccent: some View {
        Rectangle()
            .fill(accentColor)
            .frame(height: 3)
            .opacity(isHovered ? 1 : 0.5)
            .shadow(color: isHovered ? accentColor.opacity(0.8) : .clear, radius: 12)
    }

    private var cardGlare: some View {
        RadialGradient(
            colors: [
                Color.white.opacity(isHovered ? 0.12 : 0),
                Color.white.opacity(0)
            ],
            center: hoverPoint,
            startRadius: 0,
            endRadius: 100
        )
        .blendMode(.overlay)
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
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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
            .scaleEffect(isHovered ? 1.02 : 1)
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
                        .init(color: primaryColor, location: max(0, shimmerOffset)),
                        .init(color: highlightColor, location: min(1, shimmerOffset + 0.5)),
                        .init(color: primaryColor, location: min(1, shimmerOffset + 1.0)),
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
