import AppKit
import Foundation

public enum ExternalURLPolicy {
    public static func validatedHTTPSURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else {
            return nil
        }

        return url
    }
}

public enum ExternalURLOpenError: Error, Equatable {
    case invalidURL(String)
    case openRejected(String)
}

public protocol ExternalURLStringOpening: Sendable {
    @MainActor
    func openHTTPSURLString(_ value: String) throws
}

public protocol ExternalURLPlatformOpening: Sendable {
    @MainActor
    func open(_ url: URL) -> Bool
}

public struct NSWorkspaceExternalURLPlatformOpener: ExternalURLPlatformOpening {
    public init() {}

    @MainActor
    public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

public struct NSWorkspaceExternalURLStringOpener: ExternalURLStringOpening {
    private let platformOpener: any ExternalURLPlatformOpening

    public init(platformOpener: any ExternalURLPlatformOpening = NSWorkspaceExternalURLPlatformOpener()) {
        self.platformOpener = platformOpener
    }

    @MainActor
    public func openHTTPSURLString(_ value: String) throws {
        guard let url = ExternalURLPolicy.validatedHTTPSURL(value) else {
            throw ExternalURLOpenError.invalidURL(value)
        }
        guard platformOpener.open(url) else {
            throw ExternalURLOpenError.openRejected(value)
        }
    }
}
