import Foundation

func temporaryClassifierRuleEditorRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixClassifierRuleEditor")
}

func classifierYaml(_ repoURL: URL) throws -> String {
    let url = repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
    return try String(contentsOf: url, encoding: .utf8)
}
