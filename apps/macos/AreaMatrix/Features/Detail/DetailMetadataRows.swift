import SwiftUI

struct DetailMetaMetadataRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}

struct DetailMetadataRows: View {
    let detail: FileEntrySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(detailMetaMetadataRows(for: detail)) { row in
                DetailMetadataRow(label: row.label, value: row.value)
            }
        }
    }
}

private struct DetailMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

func detailMetaMetadataRows(for detail: FileEntrySnapshot) -> [DetailMetaMetadataRow] {
    var rows: [DetailMetaMetadataRow] = []
    rows.append(DetailMetaMetadataRow(label: L10n.string("Category"), value: detail.category))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Path"), value: detail.path))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Size"), value: detail.sizeDisplay))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Storage"), value: detail.storageMode))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Origin"), value: detail.origin))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Imported"), value: detail.importedAtDisplay))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Modified"), value: detail.updatedAtDisplay))
    rows.append(DetailMetaMetadataRow(label: L10n.string("SHA-256"), value: detail.hashSha256))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Source"), value: detailMetaDisplayValue(detail.sourcePath)))
    rows.append(DetailMetaMetadataRow(label: L10n.string("Status"), value: detail.statusDisplay))
    return rows
}

private func detailMetaDisplayValue(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return L10n.string("Not available") }
    return value
}
