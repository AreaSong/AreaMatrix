import Foundation

extension FilesImportReviewModel {
    static func fileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    static func isICloudPlaceholder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else {
            return false
        }
        return status == .notDownloaded
    }

    static func sourceLocation(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? url.deletingLastPathComponent().path : parent
    }

    static func defaultFilename(for items: [FilesImportPreviewItem]) -> String {
        if items.count == 1, let first = items.first {
            return first.displayName
        }
        return items.isEmpty ? "" : "\(items.count) selected items"
    }

    static func normalizedCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "inbox" : trimmed
    }

    static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func keepBothFilename(for filename: String) -> String {
        let safe = safeFilename(filename)
        let source = safe.isEmpty ? "Imported File" : safe
        let url = URL(fileURLWithPath: source)
        let fileExtension = url.pathExtension
        let basename = url.deletingPathExtension().lastPathComponent
        if fileExtension.isEmpty {
            return "\(basename) (2)"
        }
        return "\(basename) (2).\(fileExtension)"
    }

    static func targetRelativePath(category: String, filename: String) -> String {
        "\(normalizedCategory(category))/\(safeFilename(filename))"
    }
}
