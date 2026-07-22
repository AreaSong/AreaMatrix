import Foundation

enum ClassifierSettingsErrorFactory {
    static func loadError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsLoadError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsLoadError(
                message: mapping.userMessage,
                recovery: L10n.string("Retry status")
            )
        }

        return ClassifierSettingsLoadError(
            message: error.localizedDescription,
            recovery: L10n.string("Retry status after the repository is available.")
        )
    }

    static func saveError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsSaveError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsSaveError(
                message: mapping.userMessage,
                recovery: L10n.string("Retry save")
            )
        }

        return ClassifierSettingsSaveError(
            message: error.localizedDescription,
            recovery: L10n.string("Retry save after the repository is available.")
        )
    }

    static func previewError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsPreviewError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsPreviewError(
                message: mapping.userMessage,
                recovery: L10n.string("Retry preview")
            )
        }

        return ClassifierSettingsPreviewError(
            message: error.localizedDescription,
            recovery: L10n.string("Retry preview after the repository is available.")
        )
    }

    static func validationError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsValidationError {
        if let context = await mapper.mapCoreErrorContextIfPresent(error) {
            if context.kind == .config {
                return ClassifierSettingsValidationError(
                    message: context.mapping.userMessage,
                    recovery: L10n.string("Open classifier.yaml and fix the reported configuration error.")
                )
            }

            return ClassifierSettingsValidationError(
                message: context.mapping.userMessage,
                recovery: L10n.string("Review the reported error, then validate classifier.yaml again.")
            )
        }

        return ClassifierSettingsValidationError(
            message: error.localizedDescription,
            recovery: L10n.string("Open classifier.yaml and try again.")
        )
    }
}
