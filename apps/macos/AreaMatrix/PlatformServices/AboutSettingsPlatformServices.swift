import AppKit
import Foundation

enum AboutSettingsPlatformServices {
    static func makeExternalLinkOpener(
        externalURLOpener: any ExternalURLStringOpening
    ) -> any AboutExternalLinkOpening {
        NSWorkspaceAboutExternalLinkOpener(
            externalURLOpener: externalURLOpener
        )
    }

    static func makeStringCopier(writer: any PasteboardStringWriting) -> any AboutStringCopying {
        NSPasteboardAboutStringCopier(writer: writer)
    }
}

struct NSWorkspaceAboutExternalLinkOpener: AboutExternalLinkOpening {
    private let externalURLOpener: any ExternalURLStringOpening

    init(externalURLOpener: any ExternalURLStringOpening) {
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

    init(writer: any PasteboardStringWriting) {
        self.writer = writer
    }

    @MainActor
    func copy(_ value: String) throws {
        guard writer.write(value) else {
            throw AboutSettingsPlatformError.copyRejected
        }
    }
}
