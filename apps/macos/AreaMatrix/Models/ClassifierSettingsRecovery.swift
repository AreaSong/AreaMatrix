import Foundation

struct ClassifierSettingsLoadError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsSaveError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsPreviewError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsFileActionError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsValidationError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsPendingSave: Equatable {
    var config: RepoConfigSnapshot
    var error: ClassifierSettingsSaveError
}

struct ClassifierSettingsDraft: Equatable {
    var enableExtensionRules: Bool
    var enableKeywordRules: Bool
    var fallbackToInbox: Bool

    init(config: RepoConfigSnapshot) {
        enableExtensionRules = config.enableExtensionRules
        enableKeywordRules = config.enableKeywordRules
        fallbackToInbox = config.fallbackToInbox
    }
}

protocol ClassifierRulesManaging {
    func classifierFileExists(repoPath: String) -> Bool
    func lastValidBackupExists(repoPath: String) -> Bool
    func createDefaultClassifier(repoPath: String) throws
    func storeLastValidBackup(repoPath: String) throws
    func restoreLastValidBackup(repoPath: String) throws
}

struct FileSystemClassifierRulesManager: ClassifierRulesManaging {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func classifierFileExists(repoPath: String) -> Bool {
        guard let url = try? classifierURL(repoPath: repoPath) else {
            return false
        }

        return fileManager.fileExists(atPath: url.path)
    }

    func lastValidBackupExists(repoPath: String) -> Bool {
        guard let url = try? lastValidBackupURL(repoPath: repoPath) else {
            return false
        }

        return fileManager.fileExists(atPath: url.path)
    }

    func createDefaultClassifier(repoPath: String) throws {
        let metadataURL = try metadataURL(repoPath: repoPath)
        let classifierURL = try classifierURL(repoPath: repoPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: metadataURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ClassifierRulesFileError.metadataDirectoryMissing
        }
        guard !fileManager.fileExists(atPath: classifierURL.path) else {
            throw ClassifierRulesFileError.classifierAlreadyExists
        }

        try Self.defaultClassifierYAML.write(to: classifierURL, atomically: true, encoding: .utf8)
    }

    func storeLastValidBackup(repoPath: String) throws {
        let classifierURL = try classifierURL(repoPath: repoPath)
        guard fileManager.fileExists(atPath: classifierURL.path) else {
            throw ClassifierRulesFileError.classifierMissing
        }

        let content = try String(contentsOf: classifierURL, encoding: .utf8)
        let backupURL = try lastValidBackupURL(repoPath: repoPath)
        try content.write(to: backupURL, atomically: true, encoding: .utf8)
    }

    func restoreLastValidBackup(repoPath: String) throws {
        let backupURL = try lastValidBackupURL(repoPath: repoPath)
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw ClassifierRulesFileError.lastValidBackupMissing
        }

        let content = try String(contentsOf: backupURL, encoding: .utf8)
        let targetURL = try classifierURL(repoPath: repoPath)
        try content.write(to: targetURL, atomically: true, encoding: .utf8)
    }

    private func repositoryURL(repoPath: String) throws -> URL {
        let trimmed = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClassifierRulesFileError.invalidRepositoryPath
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    }

    private func metadataURL(repoPath: String) throws -> URL {
        let repoURL = try repositoryURL(repoPath: repoPath)
        return repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    }

    private func classifierURL(repoPath: String) throws -> URL {
        let metadataURL = try metadataURL(repoPath: repoPath)
        return metadataURL.appendingPathComponent("classifier.yaml", isDirectory: false)
    }

    private func lastValidBackupURL(repoPath: String) throws -> URL {
        let metadataURL = try metadataURL(repoPath: repoPath)
        return metadataURL.appendingPathComponent("classifier.last-valid.yaml", isDirectory: false)
    }

    /// Kept aligned with the Stage 1 Core default until Core exposes a default-classifier writer.
    private static let defaultClassifierYAML = """
    version: 1
    default: inbox
    categories:
      - slug: docs
        display_name: { zh-Hans: 文档, en: Documents }
        extensions: [pdf, docx, txt, md, rtf]
        keywords: [report, manual, doc, 报告, 手册]

      - slug: code
        display_name: { zh-Hans: 代码, en: Code }
        extensions: [rs, swift, py, js, ts, go, java, cpp, h, hpp, c]

      - slug: design
        display_name: { zh-Hans: 设计, en: Design }
        extensions: [psd, ai, sketch, fig, xd]
        keywords: [design, mockup, wireframe, 设计稿, 原型]

      - slug: media
        display_name: { zh-Hans: 媒体, en: Media }
        extensions: [png, jpg, jpeg, gif, mp4, mov, mp3, wav]

      - slug: finance
        display_name: { zh-Hans: 财务, en: Finance }
        keywords: [invoice, receipt, tax, contract, 发票, 收据, 税务, 合同, 报销]
        priority: 10

      - slug: inbox
        display_name: { zh-Hans: 未分类, en: Inbox }
    """
}

enum ClassifierRulesFileError: Error, Equatable, LocalizedError {
    case invalidRepositoryPath
    case metadataDirectoryMissing
    case classifierAlreadyExists
    case classifierMissing
    case lastValidBackupMissing

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryPath:
            "repository path is empty."
        case .metadataDirectoryMissing:
            ".areamatrix metadata directory is missing."
        case .classifierAlreadyExists:
            "classifier.yaml already exists."
        case .classifierMissing:
            "classifier.yaml is missing."
        case .lastValidBackupMissing:
            "last valid classifier backup is missing."
        }
    }
}

extension RepoConfigSnapshot {
    func withClassifierRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withClassifierEnableExtensionRules(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.enableExtensionRules = value
        return config
    }

    func withClassifierEnableKeywordRules(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.enableKeywordRules = value
        return config
    }

    func withClassifierFallbackToInbox(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.fallbackToInbox = value
        return config
    }
}

enum ClassifierValidationErrorFormatter {
    static func message(coreReason: String, mappedMessage: String) -> String {
        let field = firstField(in: coreReason) ?? firstField(in: mappedMessage)
        let line = firstLine(in: coreReason) ?? firstLine(in: mappedMessage)
        let details = [field.map { "field \($0)" }, line.map { "line \($0)" }].compactMap { $0 }
        guard !details.isEmpty else {
            return mappedMessage
        }

        return "\(mappedMessage) (\(details.joined(separator: ", ")))"
    }

    private static func firstField(in text: String) -> String? {
        firstMatch(pattern: #"categories\[\d+\]\.[A-Za-z_][A-Za-z0-9_]*"#, text: text)
            ?? firstMatch(pattern: #"`([^`]+)`"#, text: text, group: 1)
    }

    private static func firstLine(in text: String) -> String? {
        firstMatch(pattern: #"line\s+(\d+)"#, text: text, group: 1)
    }

    private static func firstMatch(pattern: String, text: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let textRange = Range(match.range(at: group), in: text)
        else {
            return nil
        }

        return String(text[textRange])
    }
}
