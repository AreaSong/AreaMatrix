import Foundation

@MainActor
extension ImportBatchCopyImportModel {
    func applyNamingStrategy(to row: ImportBatchCopyImportRow) -> ImportBatchCopyImportRow {
        var namedRow = row
        switch selectedNamingStrategy {
        case .suggestedName:
            break
        case .originalName:
            namedRow.suggestedName = row.originalName
        case .normalizedCharacters:
            namedRow.suggestedName = normalizedFilename(row.originalName)
        case .uniformPrefix:
            namedRow.suggestedName = prefixedFilename(row.originalName)
        }
        return namedRow
    }

    func targetRelativePath(
        for row: ImportBatchCopyImportRow,
        destination: ImportBatchDestinationOption
    ) -> String {
        let filename = row.resolvedIncomingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let categoryOverride = row.categoryOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !categoryOverride.isEmpty {
            return "\(categoryOverride)/\(filename)"
        }
        return defaultTargetRelativePath(filename: filename, row: row, destination: destination)
    }

    func entryDestination(
        for row: ImportBatchCopyImportRow,
        selectedDestination: ImportBatchDestinationOption
    ) -> ImportEntryDestination {
        if let category = row.categoryOverride {
            return .category(category)
        }
        return selectedDestination.entryDestination
    }

    func currentCategoryOverridesByRowID() -> [ImportBatchCopyImportRow.ID: String] {
        rows.reduce(into: [:]) { overrides, row in
            guard let categoryOverride = row.categoryOverride else { return }
            overrides[row.id] = categoryOverride
        }
    }

    func restoreCategoryOverride(
        for row: ImportBatchCopyImportRow,
        from overrides: [ImportBatchCopyImportRow.ID: String]
    ) -> ImportBatchCopyImportRow {
        guard let categoryOverride = overrides[row.id] else { return row }
        var restoredRow = row
        restoredRow.categoryOverride = categoryOverride
        return restoredRow
    }

    private func normalizedFilename(_ filename: String) -> String {
        filename.importBatchNormalizedFilename
    }

    private func prefixedFilename(_ filename: String) -> String {
        let prefix = namingPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return filename }
        return "\(prefix)-\(normalizedFilename(filename))"
    }

    private func defaultTargetRelativePath(
        filename: String,
        row: ImportBatchCopyImportRow,
        destination: ImportBatchDestinationOption
    ) -> String {
        switch destination {
        case .autoClassify:
            let category = (row.resolvedCategory(for: destination) ?? "inbox")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return category.isEmpty ? filename : "\(category)/\(filename)"
        case .category(let slug):
            let category = (row.resolvedCategory(for: destination) ?? slug)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return category.isEmpty ? filename : "\(category)/\(filename)"
        case .repositoryRoot:
            return filename
        }
    }
}
