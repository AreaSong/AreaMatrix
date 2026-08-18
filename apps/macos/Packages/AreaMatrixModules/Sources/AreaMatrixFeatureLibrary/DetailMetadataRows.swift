import SwiftUI

public struct DetailMetadataRow: Equatable, Identifiable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var id: String {
        label
    }
}

public struct DetailMetadataRows: View {
    private let rows: [DetailMetadataRow]

    public init(rows: [DetailMetadataRow]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
    }
}
