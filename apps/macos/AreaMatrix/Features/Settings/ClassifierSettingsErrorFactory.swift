import Foundation

enum ClassifierSettingsErrorFactory {
    static func loadError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsLoadError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsLoadError(
                message: mapping.userMessageDescriptor,
                recovery: L10n.message("Retry status")
            )
        }

        return ClassifierSettingsLoadError(
            message: L10n.message("settings.error.loadClassifier", technicalDetail: error.localizedDescription),
            recovery: L10n.message("Retry status after the repository is available.")
        )
    }

    static func saveError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsSaveError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsSaveError(
                message: mapping.userMessageDescriptor,
                recovery: L10n.message("Retry save")
            )
        }

        return ClassifierSettingsSaveError(
            message: L10n.message("Could not save classifier settings", technicalDetail: error.localizedDescription),
            recovery: L10n.message("Retry save after the repository is available.")
        )
    }

    static func previewError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsPreviewError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsPreviewError(
                message: mapping.userMessageDescriptor,
                recovery: L10n.message("Retry preview")
            )
        }

        return ClassifierSettingsPreviewError(
            message: L10n.message("Could not preview classifier settings", technicalDetail: error.localizedDescription),
            recovery: L10n.message("Retry preview after the repository is available.")
        )
    }

    static func validationError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsValidationError {
        if let context = await mapper.mapCoreErrorContextIfPresent(error) {
            if context.kind == .config {
                return ClassifierSettingsValidationError(
                    message: context.mapping.userMessageDescriptor,
                    recovery: L10n.message("Open classifier.yaml and fix the reported configuration error.")
                )
            }

            return ClassifierSettingsValidationError(
                message: context.mapping.userMessageDescriptor,
                recovery: L10n.message("Review the reported error, then validate classifier.yaml again.")
            )
        }

        return ClassifierSettingsValidationError(
            message: L10n.message(
                "settings.classifier.error.validationFailed",
                technicalDetail: error.localizedDescription
            ),
            recovery: L10n.message("Open classifier.yaml and try again.")
        )
    }
}
