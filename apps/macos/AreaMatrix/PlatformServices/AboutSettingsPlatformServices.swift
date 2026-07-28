import AppKit
import Foundation

enum AboutSettingsPlatformServices {
    static var appVersionReader: any AppVersionReading {
        AppPlatformServices.appVersionReader
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        AppPlatformServices.existingRepositoryMetadataReader
    }

    static var externalLinkOpener: any AboutExternalLinkOpening {
        NSWorkspaceAboutExternalLinkOpener()
    }

    static var stringCopier: any AboutStringCopying {
        NSPasteboardAboutStringCopier()
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        AppPlatformServices.accessibilityAnnouncer
    }
}

enum PlatformDifferencesPlatformServices {
    static var appVersionReader: any AppVersionReading {
        AppPlatformServices.appVersionReader
    }
}

struct NSWorkspaceAboutExternalLinkOpener: AboutExternalLinkOpening {
    private let externalURLOpener: any ExternalURLStringOpening

    init(externalURLOpener: any ExternalURLStringOpening = AppPlatformServices.externalURLStringOpener) {
        self.externalURLOpener = externalURLOpener
    }

    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        do {
            try externalURLOpener.openHTTPSURLString(link.urlString)
        } catch let error as ExternalURLOpenError {
            switch error {
            case .invalidURL:
                throw AboutSettingsPlatformError.invalidURL(link.urlString)
            case .openRejected:
                throw AboutSettingsPlatformError.openRejected(link.urlString)
            }
        } catch {
            throw AboutSettingsPlatformError.invalidURL(link.urlString)
        }
        return link.urlString
    }
}

struct NSPasteboardAboutStringCopier: AboutStringCopying {
    private let writer: any PasteboardStringWriting

    init(writer: any PasteboardStringWriting = AppPlatformServices.pasteboardStringWriter) {
        self.writer = writer
    }

    @MainActor
    func copy(_ value: String) throws {
        guard writer.write(value) else {
            throw AboutSettingsPlatformError.copyRejected
        }
    }
}
