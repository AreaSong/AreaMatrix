import SwiftUI

struct MobileLibraryFileRow: View {
    let file: MobileLibraryFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .foregroundStyle(file.needsReview ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.currentName)
                    .font(.headline)
                Text(file.categoryPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(file.needsReview ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fileIcon: String {
        file.needsReview ? "exclamationmark.triangle" : "doc"
    }

    private var statusText: String {
        if file.needsReview {
            return file.availability.statusText
        }
        return ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }

    private var accessibilityLabel: String {
        "\(file.currentName), \(file.categoryPath), \(file.availability.statusText)"
    }
}

extension View {
    @ViewBuilder
    func mobileLibraryListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}
