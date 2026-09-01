import Foundation

/// Coordinates extension termination with an in-flight save.
///
/// The UIKit host owns this bridge so every terminal path can cancel and await
/// the same model-owned operation before ending the extension request.
@MainActor
public final class ShareImportExtensionLifecycle {
    private weak var model: ShareImportModel?

    public init() {}

    func attach(model: ShareImportModel) {
        self.model = model
    }

    public func cancel() {
        model?.cancelSave()
    }

    public func cancelAndWait() async {
        await model?.cancelSaveAndWait()
    }
}
