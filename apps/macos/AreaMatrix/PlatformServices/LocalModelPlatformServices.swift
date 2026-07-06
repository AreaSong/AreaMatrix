import AppKit
import Foundation

enum LocalModelStatusPlatformServices {
    static var storageLocationProvider: any LocalModelStorageLocationProviding {
        LocalModelStorageProvider()
    }

    static var installHelpOpener: any LocalModelInstallHelpOpening {
        NSWorkspaceLocalModelInstallHelpOpener()
    }

    static var folderOpener: any LocalModelFolderOpening {
        NSWorkspaceLocalModelFolderOpener()
    }

    static var diagnosticsCopier: any LocalModelDiagnosticsCopying {
        NSPasteboardLocalModelDiagnosticsCopier()
    }
}

struct LocalModelStorageProvider: LocalModelStorageLocationProviding {
    func defaultStorageLocation() -> String {
        if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return supportURL
                .appendingPathComponent("AreaMatrix", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .path
        }
        return NSHomeDirectory() + "/Library/Application Support/AreaMatrix/Models"
    }
}

struct NSWorkspaceLocalModelInstallHelpOpener: LocalModelInstallHelpOpening {
    private static let installHelpURLString = "https://github.com/AreaSong/AreaMatrix"

    private let externalURLOpener: any ExternalURLStringOpening

    init(externalURLOpener: any ExternalURLStringOpening = AppPlatformServices.externalURLStringOpener) {
        self.externalURLOpener = externalURLOpener
    }

    @MainActor
    func openLocalModelInstallHelp() throws {
        do {
            try externalURLOpener.openHTTPSURLString(Self.installHelpURLString)
        } catch let error as ExternalURLOpenError {
            switch error {
            case .invalidURL:
                throw LocalModelStatusActionError.unavailable
            case .openRejected:
                throw LocalModelStatusActionError.openRejected
            }
        } catch {
            throw LocalModelStatusActionError.unavailable
        }
    }
}

struct NSWorkspaceLocalModelFolderOpener: LocalModelFolderOpening {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws {
        guard location.openable else {
            throw LocalModelStatusActionError.unavailable
        }
        do {
            let folderURL = URL(fileURLWithPath: location.folderPath, isDirectory: true)
            try localURLOpener.openExisting(folderURL, requiresDirectory: true)
        } catch {
            throw LocalModelStatusActionError.openRejected
        }
    }
}

struct NSPasteboardLocalModelDiagnosticsCopier: LocalModelDiagnosticsCopying {
    private let writer: any PasteboardStringWriting

    init(writer: any PasteboardStringWriting = AppPlatformServices.pasteboardStringWriter) {
        self.writer = writer
    }

    @MainActor
    func copyLocalModelDiagnostics(_ summary: String) throws {
        guard writer.write(summary) else {
            throw LocalModelStatusActionError.copyRejected
        }
    }
}

enum LocalModelStatusActionError: Error, Equatable, LocalizedError {
    case unavailable
    case openRejected
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The requested local model action is unavailable."
        case .openRejected:
            "macOS rejected the local model action."
        case .copyRejected:
            "macOS rejected copying diagnostics."
        }
    }
}
