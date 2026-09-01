import AreaMatrixFeatureLibrary

func detailMetaMetadataRows(for detail: FileEntrySnapshot) -> [DetailMetadataRow] {
    var rows: [DetailMetadataRow] = []
    rows.append(DetailMetadataRow(label: L10n.string("Category"), value: detail.category))
    rows.append(DetailMetadataRow(label: L10n.string("Path"), value: detail.path))
    rows.append(DetailMetadataRow(label: L10n.string("Size"), value: detail.sizeDisplay))
    rows.append(DetailMetadataRow(label: L10n.string("Storage"), value: detail.storageMode))
    rows.append(DetailMetadataRow(label: L10n.string("Origin"), value: detail.origin))
    rows.append(DetailMetadataRow(label: L10n.string("Imported"), value: detail.importedAtDisplay))
    rows.append(DetailMetadataRow(label: L10n.string("Modified"), value: detail.updatedAtDisplay))
    rows.append(DetailMetadataRow(label: L10n.string("SHA-256"), value: detail.hashSha256))
    rows.append(DetailMetadataRow(label: L10n.string("Source"), value: detailMetaDisplayValue(detail.sourcePath)))
    rows.append(DetailMetadataRow(label: L10n.string("Status"), value: detail.statusDisplay))
    return rows
}

private func detailMetaDisplayValue(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return L10n.string("Not available") }
    return value
}
