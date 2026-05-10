import Foundation

struct ImportFolderSkippedRule: Equatable, Identifiable {
    var label: String
    var count: Int

    var id: String {
        label
    }
}

struct ImportFolderScanError: Equatable, Identifiable {
    var path: String
    var message: String

    var id: String {
        "\(path)::\(message)"
    }
}
