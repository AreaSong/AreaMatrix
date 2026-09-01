#if os(iOS)
import AreaMatrixIOS
import SwiftUI
import UIKit

@MainActor
final class ShareImportViewController: UIViewController {
    private enum TerminalOutcome: Equatable {
        case completed
        case cancelled
        case expired
    }

    private enum HostState: Equatable {
        case active
        case openingAreaMatrix
        case finishing(TerminalOutcome)
        case completed
        case cancelled
        case expired
    }

    private var hostingController: UIHostingController<ShareImportExtensionScene>?
    private let lifecycle = ShareImportExtensionLifecycle()
    private var hostState: HostState = .active
    private var terminationTask: Task<Void, Never>?
    private var hostLifecycleObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        hostLifecycleObserver = NotificationCenter.default.addObserver(
            forName: .NSExtensionHostWillResignActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.expireRequest()
            }
        }
        installShareImportScene()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard hostState == .active else { return }
        cancelRequest()
    }

    private func installShareImportScene() {
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let scene = ShareImportExtensionScene(
            inputItems: inputItems,
            onCancel: { [weak self] in self?.cancelRequest() },
            onOpenAreaMatrix: { [weak self] in self?.openAreaMatrix() },
            onRequestComplete: { [weak self] in self?.completeRequest() },
            lifecycle: lifecycle
        )
        let controller = UIHostingController(rootView: scene)
        hostingController = controller
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }

    private func openAreaMatrix() {
        guard hostState == .active else { return }
        hostState = .openingAreaMatrix
        guard let url = URL(string: "areamatrix://share-import") else {
            completeRequest()
            return
        }
        guard let context = extensionContext else {
            completeRequest()
            return
        }
        context.open(url) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.completeRequest()
            }
        }
    }

    private func completeRequest() {
        guard hostState == .active || hostState == .openingAreaMatrix else { return }
        finish(.completed)
    }

    private func cancelRequest() {
        guard hostState == .active else { return }
        finish(.cancelled)
    }

    private func expireRequest() {
        guard hostState == .active else { return }
        finish(.expired)
    }

    private func finish(_ outcome: TerminalOutcome) {
        guard hostState == .active || hostState == .openingAreaMatrix else { return }
        hostState = .finishing(outcome)
        lifecycle.cancel()
        terminationTask?.cancel()
        let lifecycle = lifecycle
        terminationTask = Task { @MainActor [weak self, lifecycle] in
            await lifecycle.cancelAndWait()
            guard let self,
                  hostState == .finishing(outcome) else { return }
            stopObservingHostLifecycle()
            switch outcome {
            case .completed:
                guard let context = extensionContext else {
                    hostState = .completed
                    terminationTask = nil
                    return
                }
                terminationTask = nil
                context.completeRequest(returningItems: nil) { [weak self] expired in
                    Task { @MainActor [weak self] in
                        self?.hostCompletionDidFinish(expired: expired)
                    }
                }
            case .cancelled:
                hostState = .cancelled
                terminationTask = nil
                extensionContext?.cancelRequest(withError: cancellationError)
            case .expired:
                hostState = .expired
                terminationTask = nil
                extensionContext?.cancelRequest(withError: expirationError)
            }
        }
    }

    private func hostCompletionDidFinish(expired: Bool) {
        guard hostState == .finishing(.completed) else { return }
        hostState = expired ? .expired : .completed
    }

    private func stopObservingHostLifecycle() {
        if let hostLifecycleObserver {
            NotificationCenter.default.removeObserver(hostLifecycleObserver)
            self.hostLifecycleObserver = nil
        }
    }

    private var cancellationError: NSError {
        NSError(
            domain: "AreaMatrixShareExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Share import cancelled."]
        )
    }

    private var expirationError: NSError {
        NSError(
            domain: "AreaMatrixShareExtension",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Share import expired."]
        )
    }
}
#endif
