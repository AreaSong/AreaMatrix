import AppKit
import Foundation

protocol RootOverviewFileInspecting: Sendable {
    func status(repoPath: String) -> RootOverviewFileStatus
}

struct LocalModelStatusError: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

protocol LocalModelInstallHelpOpening: Sendable {
    @MainActor
    func openLocalModelInstallHelp() throws
}

protocol LocalModelFolderOpening: Sendable {
    @MainActor
    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws
}

protocol LocalModelDiagnosticsCopying: Sendable {
    @MainActor
    func copyLocalModelDiagnostics(_ summary: String) throws
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

struct LocalRootOverviewFileInspector: RootOverviewFileInspecting {
    private static let beginPrefix = "<!-- AREAMATRIX:BEGIN"
    private static let endTag = "<!-- AREAMATRIX:END -->"

    func status(repoPath: String) -> RootOverviewFileStatus {
        let url = URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent("AREAMATRIX.md")
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                return .unsafe("Cannot safely update AREAMATRIX.md")
            }
            let content = try String(contentsOf: url, encoding: .utf8)
            return hasManagedBlock(content) ? .managedBlock : .userContent
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unsafe("Cannot safely update AREAMATRIX.md")
        }
    }

    private func hasManagedBlock(_ content: String) -> Bool {
        guard let begin = content.range(of: Self.beginPrefix) else {
            return false
        }
        let tail = content[begin.upperBound...]
        return tail.range(of: Self.endTag) != nil
    }
}
