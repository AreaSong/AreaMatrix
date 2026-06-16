import AppKit
import SwiftUI

struct AreaMatrixWindowChromeObserver: NSViewRepresentable {
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
