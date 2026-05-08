import Foundation

enum MainListVisibleFileFiltering {
    static func visibleFiles(
        from files: [FileEntrySnapshot],
        sidebarRow: RepositorySidebarRowSnapshot,
        filterText: String
    ) -> [FileEntrySnapshot] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { file in
            sidebarRow.contains(file) && file.matchesCurrentListFilter(query)
        }
    }
}

extension FileEntrySnapshot {
    func matchesCurrentListFilter(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }

        return currentName.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    var categoryPathDisplay: String {
        let pathPrefix = path.split(separator: "/").dropLast().joined(separator: "/")
        return pathPrefix.isEmpty ? category : pathPrefix
    }

    var sizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var importedAtDisplay: String {
        Self.mainDisplayDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(importedAt)))
    }

    var updatedAtDisplay: String {
        Self.mainDisplayDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(updatedAt)))
    }

    static let mainDisplayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
