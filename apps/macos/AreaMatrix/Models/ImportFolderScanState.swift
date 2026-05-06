import Foundation

struct ImportFolderSkippedRule: Equatable, Sendable, Identifiable {
    var label: String
    var count: Int

    var id: String { label }
}

struct ImportFolderScanError: Equatable, Sendable, Identifiable {
    var path: String
    var message: String

    var id: String { "\(path)::\(message)" }
}
