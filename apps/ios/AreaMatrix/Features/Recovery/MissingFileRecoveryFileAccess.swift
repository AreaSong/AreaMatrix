import Foundation

struct MissingFileRecoveryScopedFileAccess: Sendable {
    private let stopHandler: @Sendable () -> Void

    init(stopHandler: @escaping @Sendable () -> Void) {
        self.stopHandler = stopHandler
    }

    func stop() {
        stopHandler()
    }
}

protocol MissingFileRecoveryFileAccessing: Sendable {
    func beginAccessing(_ url: URL) throws -> MissingFileRecoveryScopedFileAccess
}

struct MissingFileRecoverySecurityScopedFileAccessService: MissingFileRecoveryFileAccessing {
    func beginAccessing(_ url: URL) throws -> MissingFileRecoveryScopedFileAccess {
        let didStart = url.startAccessingSecurityScopedResource()
        guard didStart || FileManager.default.isReadableFile(atPath: url.path) else {
            throw MissingFileRecoveryError.permissionDenied(url.path)
        }
        return MissingFileRecoveryScopedFileAccess {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
