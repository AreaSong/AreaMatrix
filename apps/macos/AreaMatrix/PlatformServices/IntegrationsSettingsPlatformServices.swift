import AppKit
import Foundation

protocol ICloudIdentityTokenReading: Sendable {
    var hasICloudIdentityToken: Bool { get }
}

protocol ICloudResourceValueReading: Sendable {
    func isUbiquitousItem(at url: URL) throws -> Bool?
}

struct FileManagerICloudIdentityTokenReader: ICloudIdentityTokenReading {
    var hasICloudIdentityToken: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}

struct URLICloudResourceValueReader: ICloudResourceValueReading {
    func isUbiquitousItem(at url: URL) throws -> Bool? {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values.isUbiquitousItem
    }
}

struct LocalICloudStatusDetector: ICloudStatusDetecting {
    private let identityTokenReader: any ICloudIdentityTokenReading
    private let resourceValueReader: any ICloudResourceValueReading

    init(
        identityTokenReader: any ICloudIdentityTokenReading = FileManagerICloudIdentityTokenReader(),
        resourceValueReader: any ICloudResourceValueReading = URLICloudResourceValueReader()
    ) {
        self.identityTokenReader = identityTokenReader
        self.resourceValueReader = resourceValueReader
    }

    func snapshot(repoPath: String, config: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        let effectivePath = config.repoPath.isEmpty ? repoPath : config.repoPath
        let url = URL(fileURLWithPath: effectivePath, isDirectory: true)

        do {
            guard let isUbiquitous = try resourceValueReader.isUbiquitousItem(at: url) else {
                return IntegrationsICloudSnapshot(repositoryLocation: .unknown, iCloudStatus: .unknown)
            }

            if !isUbiquitous {
                return IntegrationsICloudSnapshot(repositoryLocation: .localFolder, iCloudStatus: .unavailable)
            }

            let status: IntegrationsICloudStatus = identityTokenReader.hasICloudIdentityToken
                ? .available
                : .unavailable
            return IntegrationsICloudSnapshot(repositoryLocation: .iCloudDrive, iCloudStatus: status)
        } catch {
            return IntegrationsICloudSnapshot(repositoryLocation: .unknown, iCloudStatus: .unknown)
        }
    }
}

enum ICloudHelpOpenError: Error, Equatable, LocalizedError {
    case helpURLUnavailable
    case openRejected

    var errorDescription: String? {
        switch self {
        case .helpURLUnavailable:
            "iCloud help URL is unavailable."
        case .openRejected:
            "iCloud help could not be opened."
        }
    }
}

struct NSWorkspaceICloudHelpOpener: ICloudHelpOpening {
    @MainActor
    func openICloudHelp() throws {
        guard let url = URL(string: "https://support.apple.com/guide/mac-help/use-icloud-drive-mchl1a02d711/mac")
        else {
            throw ICloudHelpOpenError.helpURLUnavailable
        }

        guard NSWorkspace.shared.open(url) else {
            throw ICloudHelpOpenError.openRejected
        }
    }
}
