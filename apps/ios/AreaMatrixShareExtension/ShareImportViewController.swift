#if os(iOS)
import AreaMatrixIOS
import SwiftUI
import UIKit

final class ShareImportViewController: UIViewController {
    private var hostingController: UIHostingController<ShareImportExtensionScene>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installShareImportScene()
    }

    private func installShareImportScene() {
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let scene = ShareImportExtensionScene(
            inputItems: inputItems,
            onCancel: { [weak self] in self?.cancelRequest() },
            onOpenAreaMatrix: { [weak self] in self?.openAreaMatrix() },
            onRequestComplete: { [weak self] in self?.completeRequest() }
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
        guard let url = URL(string: "areamatrix://share-import") else {
            completeRequest()
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.completeRequest()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancelRequest() {
        let error = NSError(
            domain: "AreaMatrixShareExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Share import cancelled."]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
#endif
