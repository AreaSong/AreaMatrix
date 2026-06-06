import Foundation

@MainActor
final class CameraImportReviewModel: ObservableObject {
    @Published private(set) var phase: CameraImportPhase = .preparing
    @Published private(set) var error: CameraImportError?
    @Published private(set) var conflict: CameraImportConflict?
    @Published private(set) var importedFile: MobileLibraryFile?
    @Published private(set) var category: String = ""
    @Published private(set) var fileSizeText: String = "Calculating size..."
    @Published var filename: String {
        didSet { validateFilename() }
    }

    let sourceURL: URL

    private let repoPath: String
    private let bridge: any CameraImportCoreBridge
    private var duplicateStrategy: CameraImportDuplicateStrategy = .skip

    init(
        repoPath: String,
        sourceURL: URL,
        capturedAt: Date = Date(),
        bridge: any CameraImportCoreBridge
    ) {
        self.repoPath = repoPath
        self.sourceURL = sourceURL
        self.bridge = bridge
        filename = Self.defaultFilename(capturedAt: capturedAt)
    }

    var canImport: Bool {
        phase != .preparing
            && phase != .importing
            && filenameValidation == nil
            && error == nil
            && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filenameValidation: String? {
        if filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "File name is required."
        }
        return nil
    }

    var importButtonTitle: String {
        phase == .importing ? "Importing..." : "Import"
    }

    var progressText: String {
        switch phase {
        case .preparing:
            "Preparing photo..."
        case .ready:
            "Ready to import"
        case .importing:
            "Writing metadata..."
        case .succeeded:
            "Photo imported"
        case .failed:
            "Photo import failed"
        }
    }

    func prepare() async {
        guard phase == .preparing else { return }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            error = .unreadableSource(sourceURL.path)
            phase = .failed
            return
        }
        fileSizeText = Self.fileSizeText(for: sourceURL)
        do {
            let prediction = try await bridge.predictCategory(repoPath: repoPath, filename: filename)
            category = prediction.category.isEmpty ? "inbox" : prediction.category
            phase = .ready
        } catch {
            self.error = CameraImportError.map(error)
            phase = .failed
        }
    }

    func updateCategory(_ value: String) {
        category = Self.normalizedCategory(value)
        validateFilename()
    }

    func importPhoto() async {
        guard canImport else { return }
        phase = .importing
        error = nil
        conflict = nil
        do {
            let request = CameraImportCoreRequest(
                repoPath: repoPath,
                sourceURL: sourceURL,
                filename: filename,
                category: category,
                duplicateStrategy: duplicateStrategy
            )
            importedFile = try await bridge.importCapturedPhoto(request: request)
            phase = .succeeded
        } catch {
            handleImportFailure(error)
        }
    }

    func keepDuplicateAndRetry() async {
        duplicateStrategy = .keepBoth
        await importPhoto()
    }

    func keepConflictAndRetry() async {
        duplicateStrategy = .keepBoth
        await importPhoto()
    }

    func retry() async {
        await importPhoto()
    }

    private func validateFilename() {
        if filenameValidation != nil {
            error = nil
        }
    }

    private func handleImportFailure(_ thrownError: Error) {
        let mapped = CameraImportError.map(thrownError)
        if case let .duplicateContent(existingPath) = mapped {
            conflict = .duplicateContent(existingPath: existingPath)
            phase = .ready
        } else if case let .nameConflict(existingPath) = mapped {
            let resolvedFilename = Self.keepBothFilename(for: filename)
            filename = resolvedFilename
            duplicateStrategy = .keepBoth
            conflict = .nameConflict(existingPath: existingPath, resolvedFilename: resolvedFilename)
            phase = .ready
        } else {
            error = mapped
            phase = .failed
        }
    }

    private static func defaultFilename(capturedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "Photo \(formatter.string(from: capturedAt)).jpg"
    }

    private static func fileSizeText(for url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private static func normalizedCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "inbox" : trimmed
    }

    private static func keepBothFilename(for filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? defaultFilename(capturedAt: Date()) : trimmed
        let url = URL(fileURLWithPath: source)
        let fileExtension = url.pathExtension
        let basename = url.deletingPathExtension().lastPathComponent
        if fileExtension.isEmpty {
            return "\(basename) (2)"
        }
        return "\(basename) (2).\(fileExtension)"
    }
}

enum CameraImportPhase: Equatable {
    case preparing
    case ready
    case importing
    case succeeded
    case failed
}

enum CameraImportConflict: Equatable {
    case duplicateContent(existingPath: String)
    case nameConflict(existingPath: String, resolvedFilename: String)

    var title: String {
        switch self {
        case .duplicateContent:
            "Duplicate content"
        case .nameConflict:
            "Name conflict"
        }
    }

    var message: String {
        switch self {
        case let .duplicateContent(existingPath):
            "This photo matches \(existingPath). Skip duplicate is selected by default."
        case let .nameConflict(existingPath, resolvedFilename):
            "A file already exists at \(existingPath). Keep both is selected by default; this photo will import as \(resolvedFilename)."
        }
    }

    var actionTitle: String {
        switch self {
        case .duplicateContent:
            "Keep both"
        case let .nameConflict(_, resolvedFilename):
            "Import as \(resolvedFilename)"
        }
    }
}
