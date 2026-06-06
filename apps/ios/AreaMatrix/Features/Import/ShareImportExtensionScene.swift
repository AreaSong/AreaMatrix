import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct ShareImportExtensionScene: View {
    @StateObject private var loader: ShareImportExtensionLoader
    private let onCancel: () -> Void
    private let onOpenAreaMatrix: () -> Void
    private let onRequestComplete: () -> Void

    public init(
        inputItems: [NSExtensionItem],
        onCancel: @escaping () -> Void,
        onOpenAreaMatrix: @escaping () -> Void,
        onRequestComplete: @escaping () -> Void
    ) {
        _loader = StateObject(wrappedValue: ShareImportExtensionLoader(inputItems: inputItems))
        self.onCancel = onCancel
        self.onOpenAreaMatrix = onOpenAreaMatrix
        self.onRequestComplete = onRequestComplete
    }

    public var body: some View {
        Group {
            if let model = loader.model {
                ShareImportView(
                    model: model,
                    onCancel: onCancel,
                    onOpenAreaMatrix: onOpenAreaMatrix,
                    onSaved: { _ in onRequestComplete() }
                )
            } else {
                ShareImportExtensionLoadingView(
                    statusText: loader.statusText,
                    errorText: loader.errorText,
                    onCancel: onCancel,
                    onOpenAreaMatrix: onOpenAreaMatrix
                )
            }
        }
        .task {
            await loader.load()
        }
    }
}

@MainActor
private final class ShareImportExtensionLoader: ObservableObject {
    @Published private(set) var model: ShareImportModel?
    @Published private(set) var statusText = "Reading shared item..."
    @Published private(set) var errorText: String?

    private let inputItems: [NSExtensionItem]
    private let itemReader: ShareImportExtensionItemReader

    init(
        inputItems: [NSExtensionItem],
        itemReader: ShareImportExtensionItemReader = ShareImportExtensionItemReader()
    ) {
        self.inputItems = inputItems
        self.itemReader = itemReader
    }

    func load() async {
        guard model == nil, errorText == nil else { return }
        do {
            let payload = try await itemReader.payload(from: inputItems)
            model = ShareImportModel(payload: payload, bridge: LiveMobileRepositoryCoreBridge())
        } catch {
            errorText = ShareImportError.map(error).message
            statusText = "Share import failed"
        }
    }
}

private struct ShareImportExtensionLoadingView: View {
    var statusText: String
    var errorText: String?
    var onCancel: () -> Void
    var onOpenAreaMatrix: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(statusText, systemImage: statusIcon)
                        .foregroundColor(errorText == nil ? .secondary : .orange)
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if errorText != nil {
                        Button("Open AreaMatrix", action: onOpenAreaMatrix)
                    }
                }
            }
            .navigationTitle("Save to AreaMatrix")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var statusIcon: String {
        errorText == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle"
    }
}

struct ShareImportExtensionItemReader {
    private let incomingRoot: URL

    init(
        incomingRoot: URL = SharedContainerImportQueue.defaultRootURL()
            .appendingPathComponent("incoming", isDirectory: true)
    ) {
        self.incomingRoot = incomingRoot
    }

    func payload(from inputItems: [NSExtensionItem]) async throws -> ShareImportPayload {
        var items: [ShareImportItem] = []
        for item in inputItems {
            items.append(contentsOf: await attachments(from: item))
        }
        return ShareImportPayload(items: items)
    }

    private func attachments(from item: NSExtensionItem) async -> [ShareImportItem] {
        let sourceApp = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let providers = item.attachments ?? []
        var items: [ShareImportItem] = []
        for provider in providers {
            items.append(await self.item(
                from: provider,
                sourceApp: sourceApp?.isEmpty == false ? sourceApp ?? "Share Sheet" : "Share Sheet"
            ))
        }
        return items
    }

    private func item(from provider: NSItemProvider, sourceApp: String) async -> ShareImportItem {
        do {
            if let fileURL = try await loadFileURL(from: provider) {
                return previewFile(at: fileURL, sourceApp: sourceApp)
            }
            if let url = try await loadWebURL(from: provider) {
                return previewURL(url, sourceApp: sourceApp)
            }
            if let item = deferredFileItem(from: provider, sourceApp: sourceApp) {
                return item
            }
            return unsupportedItem(provider: provider, sourceApp: sourceApp)
        } catch {
            return unsupportedItem(provider: provider, sourceApp: sourceApp)
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }
        return try await provider.loadURL(typeIdentifier: UTType.fileURL.identifier)?.standardizedFileURL
    }

    private func loadWebURL(from provider: NSItemProvider) async throws -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }
        return try await provider.loadURL(typeIdentifier: UTType.url.identifier)
    }

    private func previewFile(at sourceURL: URL, sourceApp: String) -> ShareImportItem {
        let displayName = sourceURL.lastPathComponent.isEmpty ? "Shared Item" : sourceURL.lastPathComponent
        return ShareImportItem(
            sourceURL: sourceURL,
            displayName: displayName,
            sourceApp: sourceApp,
            kind: .file,
            isReadable: true
        )
    }

    private func previewURL(_ url: URL, sourceApp: String) -> ShareImportItem {
        let displayName = ShareImportItem.safeFilename(url.host(percentEncoded: false) ?? url.absoluteString) + ".url"
        return ShareImportItem(
            sourceURL: url,
            displayName: displayName,
            sourceApp: sourceApp,
            kind: .url,
            isReadable: true
        )
    }

    private func deferredFileItem(from provider: NSItemProvider, sourceApp: String) -> ShareImportItem? {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(
            where: provider.hasItemConformingToTypeIdentifier
        ) else {
            return nil
        }
        let displayName = provider.suggestedName ?? "Shared Item"
        return ShareImportItem(
            sourceURL: incomingRoot.appendingPathComponent("deferred-\(UUID().uuidString)"),
            displayName: displayName,
            sourceApp: sourceApp,
            kind: .file,
            isReadable: true,
            deferredProvider: ShareImportDeferredFileProvider(
                itemProvider: provider,
                typeIdentifier: typeIdentifier
            )
        )
    }

    private func unsupportedItem(provider: NSItemProvider, sourceApp: String) -> ShareImportItem {
        let name = provider.suggestedName ?? provider.registeredTypeIdentifiers.first ?? "Unsupported Item"
        let url = incomingRoot.appendingPathComponent("unsupported-\(UUID().uuidString)")
        return ShareImportItem(
            sourceURL: url,
            displayName: name,
            sourceApp: sourceApp,
            kind: .file,
            isReadable: false
        )
    }
}

private extension NSItemProvider {
    func loadURL(typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: Self.url(from: item))
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let text = item as? String {
            return URL(string: text)
        }
        return nil
    }
}
