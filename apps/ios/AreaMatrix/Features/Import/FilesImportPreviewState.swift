import Foundation

struct FilesImportSelection: Identifiable, Equatable {
    let id = UUID()
    var urls: [URL]
}

struct FilesImportScopedAccess: Sendable {
    private let stopHandler: @Sendable () -> Void

    init(stopHandler: @escaping @Sendable () -> Void) {
        self.stopHandler = stopHandler
    }

    func stop() {
        stopHandler()
    }
}

protocol FilesImportSecurityScopedAccessing: Sendable {
    func beginAccessing(_ url: URL) throws -> FilesImportScopedAccess
}

struct FilesImportSecurityScopedAccessService: FilesImportSecurityScopedAccessing {
    func beginAccessing(_ url: URL) throws -> FilesImportScopedAccess {
        let didStart = url.startAccessingSecurityScopedResource()
        guard didStart || FileManager.default.isReadableFile(atPath: url.path) else {
            throw FilesImportError.permissionDenied(url.path)
        }
        return FilesImportScopedAccess {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

enum FilesImportPhase: Equatable {
    case reading
    case ready
    case importing
    case succeeded
    case failed
}

enum FilesImportPreviewStatus: Equatable {
    case ready
    case unreadable
    case downloadNeeded
    case importing
    case imported
    case skippedDuplicate(String)
    case failed(String)

    var isImportable: Bool {
        self == .ready
    }

    var label: String {
        switch self {
        case .ready:
            "Ready"
        case .unreadable:
            "Unreadable"
        case .downloadNeeded:
            "Download needed"
        case .importing:
            "Importing"
        case .imported:
            "Imported"
        case .skippedDuplicate:
            "Skipped duplicate"
        case .failed:
            "Failed"
        }
    }
}

struct FilesImportPreviewItem: Equatable, Identifiable {
    var id: String { sourceURL.path }
    var sourceURL: URL
    var displayName: String
    var sourceLocation: String
    var sizeBytes: Int64?
    var status: FilesImportPreviewStatus

    var sizeText: String {
        guard let sizeBytes else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
