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
