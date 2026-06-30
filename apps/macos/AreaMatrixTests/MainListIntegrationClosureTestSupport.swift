@testable import AreaMatrix

actor MainListIntegrationSuspendedLister: CoreFileListing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return []
    }

    func waitForRequest() async {
        while !didReceiveRequest {
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

actor MainListIntegrationNoopDetailer: CoreFileDetailing {
    private var requests: [Int64] = []

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(fileID)
        throw CoreError.FileNotFound(path: "\(fileID)")
    }

    func recordedRequests() -> [Int64] {
        requests
    }
}

actor MainListIntegrationDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [Int64] = []

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(fileID)
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case let .success(file):
            return file
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [Int64] {
        requests
    }
}

actor MainListIntegrationDiagnosticsCollector: CoreDiagnosticsCollecting {
    enum Result {
        case success(DiagnosticsSnapshotSnapshot)
        case failure(Error)
    }

    private let result: Result
    private var repoPaths: [String] = []

    init(result: Result) {
        self.result = result
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func recordedRepoPaths() -> [String] {
        repoPaths
    }
}

extension RepositoryOpeningResult {
    static func integrationClosureFixture(
        repoPath: String,
        files: [FileEntrySnapshot],
        isReadOnly: Bool = false,
        writeLockedFileIDs: Set<Int64> = []
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .integrationClosureFixture(repoPath: repoPath),
            tree: .integrationClosureFixtureTree(),
            currentCategoryFiles: files,
            isReadOnly: isReadOnly,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }
}

extension RepoConfigSnapshot {
    static func integrationClosureFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func integrationClosureFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 2,
                    children: []
                )
            ]
        )
    }
}

extension FileEntrySnapshot {
    static func integrationClosureFixture(
        id: Int64,
        path: String = "docs/contracts/a.pdf",
        category: String = "docs",
        currentName: String,
        storageMode: String = "Copied",
        availability: FileAvailabilitySnapshot = .available
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "integration-closure-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100,
            availability: availability
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func integrationClosureDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: "db locked"
        )
    }
}
