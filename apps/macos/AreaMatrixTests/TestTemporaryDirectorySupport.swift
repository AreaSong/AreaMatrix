import Foundation

func makeTestTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeTestTemporaryDirectory(prefix: String, named name: String) throws -> URL {
    try makeTestTemporaryDirectory(named: "\(name)-\(prefix)")
}

func removeTestTemporaryItems(_ urls: URL..., fileManager: FileManager = .default) {
    removeTestTemporaryItems(urls, fileManager: fileManager)
}

func removeTestTemporaryItems(_ urls: [URL], fileManager: FileManager = .default) {
    for url in urls {
        removeTestTemporaryItem(url, fileManager: fileManager)
    }
}

private func removeTestTemporaryItem(_ url: URL, fileManager: FileManager) {
    guard isTestTemporaryItem(url, fileManager: fileManager) else {
        assertionFailure("Refusing to remove non-temporary test item: \(url.path)")
        return
    }

    try? fileManager.removeItem(at: url)
}

private func isTestTemporaryItem(_ url: URL, fileManager: FileManager) -> Bool {
    let temporaryDirectoryPath = fileManager.temporaryDirectory
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
    let temporaryRoot = temporaryDirectoryPath.hasSuffix("/") ? temporaryDirectoryPath : "\(temporaryDirectoryPath)/"
    let itemPath = url
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
    return itemPath.hasPrefix(temporaryRoot)
}
