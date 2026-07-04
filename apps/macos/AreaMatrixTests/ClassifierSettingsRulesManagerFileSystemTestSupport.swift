@testable import AreaMatrix
import Foundation

final class ClassifierSettingsTestRulesManager: ClassifierRulesManaging {
    private let fileManager = FileManager.default

    func classifierFileExists(repoPath: String) -> Bool {
        fileManager.fileExists(atPath: classifierFileURL(repoPath: repoPath).path)
    }

    func classifierCategorySlugs(repoPath: String) throws -> [String] {
        let yaml = try String(contentsOf: classifierFileURL(repoPath: repoPath), encoding: .utf8)
        return ClassifierRulesCategorySlugParser.slugs(in: yaml)
    }

    func lastValidBackupExists(repoPath: String) -> Bool {
        fileManager.fileExists(atPath: lastValidBackupFileURL(repoPath: repoPath).path)
    }

    func createDefaultClassifier(repoPath _: String) throws {}

    func storeLastValidBackup(repoPath: String) throws {
        let yaml = try String(contentsOf: classifierFileURL(repoPath: repoPath), encoding: .utf8)
        try yaml.write(to: lastValidBackupFileURL(repoPath: repoPath), atomically: true, encoding: .utf8)
    }

    func restoreLastValidBackup(repoPath: String) throws {
        let yaml = try String(contentsOf: lastValidBackupFileURL(repoPath: repoPath), encoding: .utf8)
        try yaml.write(to: classifierFileURL(repoPath: repoPath), atomically: true, encoding: .utf8)
    }

    func writeClassifier(repoURL: URL, slugs: [String]) throws {
        let yaml = """
        version: 1
        default: inbox
        categories:
        \(slugs.map { "  - slug: \($0)" }.joined(separator: "\n"))
        """
        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try yaml.write(to: classifierFileURL(repoPath: repoURL.path), atomically: true, encoding: .utf8)
    }

    private func classifierFileURL(repoPath: String) -> URL {
        classifierURL(repoURL: URL(fileURLWithPath: repoPath, isDirectory: true))
    }

    private func lastValidBackupFileURL(repoPath: String) -> URL {
        lastValidBackupURL(repoURL: URL(fileURLWithPath: repoPath, isDirectory: true))
    }
}
