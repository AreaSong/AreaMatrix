import AppKit
import Foundation

enum ExternalURLPolicy {
    static func validatedHTTPSURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else {
            return nil
        }

        return url
    }
}

enum ExternalURLOpenError: Error, Equatable {
    case invalidURL(String)
    case openRejected(String)
}

protocol ExternalURLStringOpening: Sendable {
    @MainActor
    func openHTTPSURLString(_ value: String) throws
}

protocol ExternalURLPlatformOpening: Sendable {
    @MainActor
    func open(_ url: URL) -> Bool
}

struct NSWorkspaceExternalURLPlatformOpener: ExternalURLPlatformOpening {
    @MainActor
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

struct NSWorkspaceExternalURLStringOpener: ExternalURLStringOpening {
    private let platformOpener: any ExternalURLPlatformOpening

    init(platformOpener: any ExternalURLPlatformOpening = NSWorkspaceExternalURLPlatformOpener()) {
        self.platformOpener = platformOpener
    }

    @MainActor
    func openHTTPSURLString(_ value: String) throws {
        guard let url = ExternalURLPolicy.validatedHTTPSURL(value) else {
            throw ExternalURLOpenError.invalidURL(value)
        }
        guard platformOpener.open(url) else {
            throw ExternalURLOpenError.openRejected(value)
        }
    }
}
