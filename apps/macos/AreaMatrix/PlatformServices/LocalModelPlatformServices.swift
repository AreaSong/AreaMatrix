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
    @MainActor
    func openLocalModelInstallHelp() throws {
        guard let url = URL(string: "https://github.com/AreaSong/AreaMatrix") else {
            throw LocalModelStatusActionError.unavailable
        }
        try openURL(url)
    }
}

struct NSWorkspaceLocalModelFolderOpener: LocalModelFolderOpening {
    @MainActor
    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws {
        guard location.openable else {
            throw LocalModelStatusActionError.unavailable
        }
        try openURL(URL(fileURLWithPath: location.folderPath, isDirectory: true))
    }
}

struct NSPasteboardLocalModelDiagnosticsCopier: LocalModelDiagnosticsCopying {
    @MainActor
    func copyLocalModelDiagnostics(_ summary: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(summary, forType: .string) else {
            throw LocalModelStatusActionError.copyRejected
        }
    }
}

@MainActor
private func openURL(_ url: URL) throws {
    guard NSWorkspace.shared.open(url) else {
        throw LocalModelStatusActionError.openRejected
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
