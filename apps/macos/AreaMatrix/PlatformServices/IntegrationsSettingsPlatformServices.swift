import AppKit
import Foundation

enum IntegrationsSettingsPlatformServices {
    static func makeStatusDetector() -> any ICloudStatusDetecting {
        LocalICloudStatusDetector()
    }

    static func makeHelpOpener(
        externalURLOpener: any ExternalURLStringOpening
    ) -> any ICloudHelpOpening {
        NSWorkspaceICloudHelpOpener(
            externalURLOpener: externalURLOpener
        )
    }
}

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

    func snapshot(repoPath: String, config: AppRepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
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
            L10n.string("settings.integrations.icloudHelpUnavailable")
        case .openRejected:
            L10n.string("settings.integrations.icloudHelpOpenRejected")
        }
    }
}

struct NSWorkspaceICloudHelpOpener: ICloudHelpOpening {
    private static let helpURLString = "https://support.apple.com/guide/mac-help/use-icloud-drive-mchl1a02d711/mac"

    private let externalURLOpener: any ExternalURLStringOpening

    init(externalURLOpener: any ExternalURLStringOpening) {
        self.externalURLOpener = externalURLOpener
    }

    @MainActor
    func openICloudHelp() throws {
        do {
            try externalURLOpener.openHTTPSURLString(Self.helpURLString)
        } catch let error as ExternalURLOpenError {
            switch error {
            case .invalidURL:
                throw ICloudHelpOpenError.helpURLUnavailable
            case .openRejected:
                throw ICloudHelpOpenError.openRejected
            }
        } catch {
            throw ICloudHelpOpenError.helpURLUnavailable
        }
    }
}
