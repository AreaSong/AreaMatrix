import AppKit
import SwiftUI

struct WindowCloseConfirmationObserver: NSViewRepresentable {
    let shouldConfirm: () -> Bool
    let onAttemptClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.shouldConfirm = shouldConfirm
        context.coordinator.onAttemptClose = onAttemptClose
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldConfirm: shouldConfirm, onAttemptClose: onAttemptClose)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldConfirm: () -> Bool
        var onAttemptClose: () -> Void
        private weak var observedWindow: NSWindow?
        private weak var previousDelegate: NSWindowDelegate?

        init(shouldConfirm: @escaping () -> Bool, onAttemptClose: @escaping () -> Void) {
            self.shouldConfirm = shouldConfirm
            self.onAttemptClose = onAttemptClose
        }

        func attach(to window: NSWindow?) {
            guard let window, observedWindow !== window else { return }
            previousDelegate = window.delegate
            window.delegate = self
            observedWindow = window
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldConfirm() else {
                return previousDelegate?.windowShouldClose?(sender) ?? true
            }

            onAttemptClose()
            return false
        }
    }
}
