import Foundation

struct FilesImportSelection: Identifiable, Equatable {
    let id = UUID()
    var urls: [URL]
}

struct FilesImportScopedAccess: Sendable {
    private let stopHandler: @Sendable () -> Void

    init(stopHandler: @escaping @Sendable () -> Void) {
        self.stopHandler = stopHandler
    }

    func stop() {
        stopHandler()
    }
}

protocol FilesImportSecurityScopedAccessing: Sendable {
    func beginAccessing(_ url: URL) throws -> FilesImportScopedAccess
}

struct FilesImportSecurityScopedAccessService: FilesImportSecurityScopedAccessing {
    func beginAccessing(_ url: URL) throws -> FilesImportScopedAccess {
        let didStart = url.startAccessingSecurityScopedResource()
        guard didStart || FileManager.default.isReadableFile(atPath: url.path) else {
            throw FilesImportError.permissionDenied(url.path)
        }
        return FilesImportScopedAccess {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

enum FilesImportPhase: Equatable {
    case reading
    case ready
    case importing
    case succeeded
    case failed
}

enum FilesImportPreviewStatus: Equatable {
    case ready
    case unreadable
    case downloadNeeded
    case importing
    case imported
    case skippedDuplicate(String)
    case failed(String)

    var isImportable: Bool {
        self == .ready
    }

    var label: String {
        switch self {
        case .ready:
            "Ready"
        case .unreadable:
            "Unreadable"
        case .downloadNeeded:
            "Download needed"
        case .importing:
            "Importing"
        case .imported:
            "Imported"
        case .skippedDuplicate:
            "Skipped duplicate"
        case .failed:
            "Failed"
        }
    }
}

struct FilesImportPreviewItem: Equatable, Identifiable {
    var id: String { sourceURL.path }
    var sourceURL: URL
    var displayName: String
    var sourceLocation: String
    var sizeBytes: Int64?
    var status: FilesImportPreviewStatus

    var sizeText: String {
        guard let sizeBytes else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

@MainActor
final class FilesImportReviewModel: ObservableObject {
    @Published private(set) var phase: FilesImportPhase = .reading
    @Published private(set) var previewItems: [FilesImportPreviewItem] = []
    @Published private(set) var error: FilesImportError?
    @Published private(set) var warning: String?
    @Published private(set) var importedFiles: [MobileLibraryFile] = []
    @Published private(set) var category: String = "inbox"
    @Published var filename: String = "" {
        didSet { validateFilename() }
    }

    private let repoPath: String
    private let selectedURLs: [URL]
    private let bridge: any FilesImportCoreBridge
    private let accessProvider: any FilesImportSecurityScopedAccessing

    init(
        repoPath: String,
        selectedURLs: [URL],
        bridge: any FilesImportCoreBridge,
        accessProvider: any FilesImportSecurityScopedAccessing = FilesImportSecurityScopedAccessService()
    ) {
        self.repoPath = repoPath
        self.selectedURLs = selectedURLs
        self.bridge = bridge
        self.accessProvider = accessProvider
    }

    var canImport: Bool {
        phase == .ready
            && error == nil
            && filenameValidation == nil
            && previewItems.contains { $0.status.isImportable }
            && !normalizedCategory.isEmpty
    }

    var allowsFilenameEditing: Bool {
        previewItems.count == 1
    }

    var filenameValidation: String? {
        if allowsFilenameEditing && Self.safeFilename(filename).isEmpty {
            return "File name is required."
        }
        return nil
    }

    var importButtonTitle: String {
        phase == .importing ? "Importing..." : "Import"
    }

    var selectedSummary: String {
        if previewItems.isEmpty {
            return "Choose files to import."
        }
        if previewItems.count == 1, let first = previewItems.first {
            return first.displayName
        }
        return "\(previewItems.count) items selected"
    }

    var totalSizeText: String {
        let sizes = previewItems.compactMap(\.sizeBytes)
        guard sizes.count == previewItems.count else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: sizes.reduce(0, +), countStyle: .file)
    }

    var statusText: String {
        switch phase {
        case .reading:
            "Reading selected files..."
        case .ready:
            "Ready to import"
        case .importing:
            "Copying files..."
        case .succeeded:
            "Imported \(importedFiles.count) items"
        case .failed:
            "Files import failed"
        }
    }

    func prepare() async {
        guard phase == .reading else { return }
        guard !selectedURLs.isEmpty else {
            error = .emptySelection
            phase = .failed
            return
        }
        previewItems = selectedURLs.map { makePreviewItem(for: $0) }
        filename = Self.defaultFilename(for: previewItems)
        await applyCategoryPrediction()
        if !previewItems.contains(where: { $0.status.isImportable }) {
            error = .unreadableFile("No readable files")
        }
        phase = error == nil ? .ready : .failed
    }

    func updateCategory(_ value: String) {
        category = Self.normalizedCategory(value)
    }

    func importFiles() async {
        guard canImport else { return }
        phase = .importing
        error = nil
        warning = nil
        importedFiles = []
        for item in previewItems where item.status.isImportable {
            await importItem(item)
        }
        if error != nil {
            phase = .failed
        } else {
            phase = importedFiles.isEmpty && !hasSkippedDuplicates ? .failed : .succeeded
        }
    }

    func retry() async {
        resetFailedItems()
        await importFiles()
    }

    private var normalizedCategory: String {
        Self.normalizedCategory(category)
    }

    private var hasSkippedDuplicates: Bool {
        previewItems.contains { item in
            if case .skippedDuplicate = item.status {
                return true
            }
            return false
        }
    }

    private func applyCategoryPrediction() async {
        guard let first = previewItems.first(where: { $0.status.isImportable }) else { return }
        do {
            let prediction = try await bridge.predictCategory(repoPath: repoPath, filename: first.displayName)
            category = prediction.category.isEmpty ? "inbox" : prediction.category
            if allowsFilenameEditing && !prediction.suggestedName.isEmpty {
                filename = Self.safeFilename(prediction.suggestedName)
            }
        } catch {
            warning = FilesImportError.map(error).message
            category = "inbox"
        }
    }

    private func importItem(_ item: FilesImportPreviewItem) async {
        updateItem(item.id, status: .importing)
        do {
            let imported = try await importWithAccess(item, filename: importFilename(for: item), strategy: .skip)
            importedFiles.append(imported)
            updateItem(item.id, status: .imported)
        } catch {
            await handleImportFailure(error, for: item)
        }
    }

    private func handleImportFailure(_ thrownError: Error, for item: FilesImportPreviewItem) async {
        let mapped = FilesImportError.map(thrownError)
        if case let .duplicateContent(existingPath) = mapped {
            updateItem(item.id, status: .skippedDuplicate(existingPath))
            return
        }
        if case let .nameConflict(existingPath) = mapped {
            await retryNameConflict(item, existingPath: existingPath)
            return
        }
        error = mapped
        updateItem(item.id, status: .failed(mapped.message))
    }

    private func retryNameConflict(_ item: FilesImportPreviewItem, existingPath: String) async {
        let resolved = Self.keepBothFilename(for: importFilename(for: item))
        do {
            let imported = try await importWithAccess(item, filename: resolved, strategy: .keepBoth)
            importedFiles.append(imported)
            updateItem(item.id, status: .imported)
        } catch {
            self.error = FilesImportError.map(error)
            updateItem(item.id, status: .failed("Name conflict: \(existingPath)"))
        }
    }

    private func importWithAccess(
        _ item: FilesImportPreviewItem,
        filename: String,
        strategy: FilesImportDuplicateStrategy
    ) async throws -> MobileLibraryFile {
        let access = try accessProvider.beginAccessing(item.sourceURL)
        defer { access.stop() }
        return try await bridge.importSelectedFile(request: FilesImportCoreRequest(
            repoPath: repoPath,
            sourceURL: item.sourceURL,
            filename: filename,
            category: normalizedCategory,
            duplicateStrategy: strategy
        ))
    }

    private func makePreviewItem(for url: URL) -> FilesImportPreviewItem {
        let status = previewStatus(for: url)
        return FilesImportPreviewItem(
            sourceURL: url,
            displayName: Self.safeFilename(url.lastPathComponent),
            sourceLocation: Self.sourceLocation(for: url),
            sizeBytes: Self.fileSize(for: url),
            status: status
        )
    }

    private func previewStatus(for url: URL) -> FilesImportPreviewStatus {
        do {
            let access = try accessProvider.beginAccessing(url)
            defer { access.stop() }
            if Self.isICloudPlaceholder(url) {
                return .downloadNeeded
            }
            return FileManager.default.isReadableFile(atPath: url.path) ? .ready : .unreadable
        } catch {
            self.error = FilesImportError.map(error)
            return .failed(FilesImportError.map(error).message)
        }
    }

    private func updateItem(_ id: String, status: FilesImportPreviewStatus) {
        guard let index = previewItems.firstIndex(where: { $0.id == id }) else { return }
        previewItems[index].status = status
    }

    private func resetFailedItems() {
        error = nil
        for item in previewItems {
            if case .failed = item.status {
                updateItem(item.id, status: .ready)
            }
        }
    }

    private func importFilename(for item: FilesImportPreviewItem) -> String {
        if allowsFilenameEditing {
            return Self.safeFilename(filename)
        }
        return item.displayName
    }

    private func validateFilename() {
        if filenameValidation == nil, error == .emptySelection {
            error = nil
        }
    }

    private static func fileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    private static func isICloudPlaceholder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else {
            return false
        }
        return status == .notDownloaded
    }

    private static func sourceLocation(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? url.deletingLastPathComponent().path : parent
    }

    private static func defaultFilename(for items: [FilesImportPreviewItem]) -> String {
        if items.count == 1, let first = items.first {
            return first.displayName
        }
        return items.isEmpty ? "" : "\(items.count) selected items"
    }

    private static func normalizedCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "inbox" : trimmed
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keepBothFilename(for filename: String) -> String {
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
}
