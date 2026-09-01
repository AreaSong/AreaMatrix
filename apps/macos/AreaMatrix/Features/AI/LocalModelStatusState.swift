import AreaMatrixFeatureAI
import Foundation

struct LocalModelStatusError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
    var detail: String
}

protocol LocalModelInstallHelpOpening: Sendable {
    @MainActor
    func openLocalModelInstallHelp() throws
}

protocol LocalModelFolderOpening: Sendable {
    @MainActor
    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws
}

protocol LocalModelDiagnosticsCopying: Sendable {
    @MainActor
    func copyLocalModelDiagnostics(_ summary: String) throws
}

protocol LocalModelStorageLocationProviding: Sendable {
    func defaultStorageLocation() -> String
}
