import Foundation

protocol RootOverviewFileInspecting: Sendable {
    func status(repoPath: String) -> RootOverviewFileStatus
}

struct LocalRootOverviewFileInspector: RootOverviewFileInspecting {
    private static let beginPrefix = "<!-- AREAMATRIX:BEGIN"
    private static let endTag = "<!-- AREAMATRIX:END -->"

    func status(repoPath: String) -> RootOverviewFileStatus {
        let url = URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent("AREAMATRIX.md")
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                return .unsafe("Cannot safely update AREAMATRIX.md")
            }
            let content = try String(contentsOf: url, encoding: .utf8)
            return hasManagedBlock(content) ? .managedBlock : .userContent
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unsafe("Cannot safely update AREAMATRIX.md")
        }
    }

    private func hasManagedBlock(_ content: String) -> Bool {
        guard let begin = content.range(of: Self.beginPrefix) else {
            return false
        }
        let tail = content[begin.upperBound...]
        return tail.range(of: Self.endTag) != nil
    }
}
