import Foundation

enum ClassifierSettingsPlatformServices {
    static var classifierRulesManager: any ClassifierRulesManaging {
        FileSystemClassifierRulesManager()
    }

    static var fileOpener: any RepositoryFileOpening {
        AppPlatformServices.fileOpener
    }

    static var fileRevealer: any RepositoryFileRevealing {
        AppPlatformServices.fileRevealer
    }

    static var finderOpener: any RepositoryFinderOpening {
        AppPlatformServices.finderOpener
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        VoiceOverAccessibilityAnnouncer()
    }
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

    func classifierCategorySlugs(repoPath: String) throws -> [String] {
        let content = try String(contentsOf: classifierURL(repoPath: repoPath), encoding: .utf8)
        return ClassifierRulesCategorySlugParser.slugs(in: content)
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

    /// Kept aligned with the Core default until Core exposes a default-classifier writer.
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
