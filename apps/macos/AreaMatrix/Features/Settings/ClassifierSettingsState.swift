import Foundation

enum ClassifierSettingsLoadState: Equatable {
    case loading
    case loaded
    case failed(ClassifierSettingsLoadError)
}

enum ClassifierSettingsValidationState: Equatable {
    case idle
    case validating
    case passed
    case failed(ClassifierSettingsValidationError)
}

enum ClassifierSettingsPaths {
    static let classifierRelativePath = ".areamatrix/classifier.yaml"
    static let validationProbeFilename = "AreaMatrixValidationProbe.txt"

    static func classifierConfigURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
    }
}
