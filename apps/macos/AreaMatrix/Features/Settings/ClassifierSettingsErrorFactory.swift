import Foundation

enum ClassifierSettingsErrorFactory {
    static func loadError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsLoadError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsLoadError(
                message: mapping.userMessage,
                recovery: "Retry status"
            )
        }

        return ClassifierSettingsLoadError(
            message: error.localizedDescription,
            recovery: "Retry status after the repository is available."
        )
    }

    static func saveError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsSaveError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsSaveError(
                message: mapping.userMessage,
                recovery: "Retry save"
            )
        }

        return ClassifierSettingsSaveError(
            message: error.localizedDescription,
            recovery: "Retry save after the repository is available."
        )
    }

    static func previewError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsPreviewError {
        if let mapping = await mapper.mapCoreErrorIfPresent(error) {
            return ClassifierSettingsPreviewError(
                message: mapping.userMessage,
                recovery: "Retry preview"
            )
        }

        return ClassifierSettingsPreviewError(
            message: error.localizedDescription,
            recovery: "Retry preview after the repository is available."
        )
    }

    static func validationError(
        for error: Error,
        mapper: any CoreErrorMapping
    ) async -> ClassifierSettingsValidationError {
        if let coreError = error as? CoreError {
            let mapping = await mapper.mapCoreError(coreError)
            if case let .Config(reason) = coreError {
                return ClassifierSettingsValidationError(
                    message: ClassifierValidationErrorFormatter.message(
                        coreReason: reason,
                        mappedMessage: mapping.userMessage
                    ),
                    recovery: "Open classifier.yaml and fix the reported line and field."
                )
            }

            return ClassifierSettingsValidationError(
                message: mapping.userMessage,
                recovery: "Open classifier.yaml and fix the reported line."
            )
        }

        return ClassifierSettingsValidationError(
            message: error.localizedDescription,
            recovery: "Open classifier.yaml and try again."
        )
    }
}
