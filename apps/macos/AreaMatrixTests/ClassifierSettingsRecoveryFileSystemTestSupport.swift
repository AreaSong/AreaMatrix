import Foundation

func temporaryClassifierRecoveryRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixClassifierRecovery")
}

func classifierURL(repoURL: URL) -> URL {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
}

func writeClassifier(_ content: String, repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try content.write(to: classifierURL(repoURL: repoURL), atomically: true, encoding: .utf8)
}
