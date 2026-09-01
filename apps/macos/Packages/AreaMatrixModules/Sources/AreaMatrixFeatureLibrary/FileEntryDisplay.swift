import AreaMatrixCoreBridgeContract
import Foundation

/// MainList-owned, non-localized projections used by table cells and sorting.
///
/// User-visible localized copy remains at the App/View boundary; these values are
/// deterministic projections of a Core snapshot and are safe to share with previews.
public enum FileEntryDisplay {
    public static func categoryPath(for file: FileEntrySnapshot) -> String {
        let pathPrefix = file.path.split(separator: "/").dropLast().joined(separator: "/")
        return pathPrefix.isEmpty ? file.category : pathPrefix
    }

    public static func size(for file: FileEntrySnapshot) -> String {
        ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }

    public static func importedAt(for file: FileEntrySnapshot) -> String {
        date(file.importedAt)
    }

    public static func updatedAt(for file: FileEntrySnapshot) -> String {
        date(file.updatedAt)
    }

    private static func date(_ timestamp: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .omitted)
    }
}
