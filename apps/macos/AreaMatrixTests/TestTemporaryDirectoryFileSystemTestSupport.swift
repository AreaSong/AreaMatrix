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

func createTestTemporaryDirectory(at url: URL, fileManager: FileManager = .default) throws {
    guard isTestTemporaryItem(url, fileManager: fileManager) else {
        throw testTemporaryBoundaryError("Refusing to create non-temporary test directory: \(url.path)")
    }
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func removeTestTemporaryItems(_ urls: URL..., fileManager: FileManager = .default) {
    removeTestTemporaryItems(urls, fileManager: fileManager)
}

func removeTestTemporaryItems(_ urls: [URL], fileManager: FileManager = .default) {
    for url in urls {
        try? removeTestTemporaryItem(url, fileManager: fileManager)
    }
}

func removeTestTemporaryItem(_ url: URL, fileManager: FileManager = .default) throws {
    guard isTestTemporaryItem(url, fileManager: fileManager) else {
        let message = "Refusing to remove non-temporary test item: \(url.path)"
        assertionFailure(message)
        throw testTemporaryBoundaryError(message)
    }

    try fileManager.removeItem(at: url)
}

private func testTemporaryBoundaryError(_ message: String) -> NSError {
    NSError(
        domain: "AreaMatrixTests.TestTemporaryDirectoryFileSystemTestSupport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
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
