import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CameraImportReviewSheet: View {
    @StateObject private var model: CameraImportReviewModel
    private let onCancel: () -> Void
    private let onRetake: () -> Void
    private let onImported: (MobileLibraryFile) -> Void

    init(
        repoPath: String,
        sourceURL: URL,
        bridge: any CameraImportCoreBridge,
        onCancel: @escaping () -> Void,
        onRetake: @escaping () -> Void,
        onImported: @escaping (MobileLibraryFile) -> Void
    ) {
        _model = StateObject(wrappedValue: CameraImportReviewModel(
            repoPath: repoPath,
            sourceURL: sourceURL,
            bridge: bridge
        ))
        self.onCancel = onCancel
        self.onRetake = onRetake
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            List {
                previewSection
                detailsSection
                conflictSection
                statusSection
            }
            .navigationTitle("Import Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.importButtonTitle) {
                        Task { await model.importPhoto() }
                    }
                    .disabled(!model.canImport)
                }
            }
            .task {
                await model.prepare()
            }
            .onChange(of: model.importedFile) { _, file in
                if let file {
                    onImported(file)
                }
            }
        }
    }

    private var previewSection: some View {
        Section {
            CapturedPhotoPreview(sourceURL: model.sourceURL)
            HStack {
                Button("Retake", action: onRetake)
                Spacer()
                Text("Source: Camera")
                    .foregroundStyle(.secondary)
            }
            Text("The original captured photo will not be deleted until import is complete or you cancel.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("File name", text: $model.filename)
                .autocorrectionDisabled()
            if let message = model.filenameValidation {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            TextField("Category", text: Binding(
                get: { model.category },
                set: { model.updateCategory($0) }
            ))
            LabeledContent("Save as", value: "Copy into repository")
            LabeledContent("File size", value: model.fileSizeText)
        }
    }

    @ViewBuilder
    private var conflictSection: some View {
        if let conflict = model.conflict {
            Section {
                Label(conflict.title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(conflict.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(conflict.actionTitle) {
                    Task { await model.keepConflictAndRetry() }
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            Label(model.progressText, systemImage: statusIcon)
                .foregroundStyle(statusColor)
            if let error = model.error {
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Retry") {
                    Task { await model.retry() }
                }
            }
        }
    }

    private var statusIcon: String {
        switch model.phase {
        case .preparing, .importing:
            "arrow.triangle.2.circlepath"
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .ready:
            "checkmark"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .failed:
            .orange
        case .succeeded:
            .green
        default:
            .secondary
        }
    }
}

private struct CapturedPhotoPreview: View {
    let sourceURL: URL
    @State private var previewImage: Image?
    @State private var previewError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewBody
                .task(id: sourceURL) {
                    await loadPreview()
                }
            Text(sourceURL.lastPathComponent)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var previewBody: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.16))
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let previewImage {
                    previewImage
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else if let previewError {
                    Label(previewError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView("Preparing photo...")
                }
            }
            .accessibilityLabel("Captured photo preview")
    }

    @MainActor
    private func loadPreview() async {
        previewImage = nil
        previewError = nil
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: sourceURL)
            }.value
            guard let image = Self.image(from: data) else {
                previewError = "Could not read captured photo."
                return
            }
            previewImage = image
        } catch {
            previewError = "Could not read captured photo."
        }
    }

    private static func image(from data: Data) -> Image? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}
