import Foundation

extension MainRepositoryContentView {
    @MainActor
    func refreshAfterCategoryMove(_ movedFile: FileEntrySnapshot) {
        Task {
            await refreshTreeAndFocusMovedFile(movedFile)
        }
    }

    @MainActor
    func refreshTreeAndFocusMovedFile(_ movedFile: FileEntrySnapshot) async {
        let refreshedTree = await refreshedTreeAfterCategoryMove()
        let plan = CategoryMoveRefreshPlan.make(
            movedFile: movedFile,
            currentSidebarID: selectedSidebarID,
            currentTree: repositoryTree,
            refreshedTree: refreshedTree
        )

        repositoryTree = plan.tree
        pendingMovedFileFocusID = movedFile.id
        selectedSidebarID = plan.selectedSidebarID
        selectedFileIDs = [movedFile.id]
        await fileListModel.loadCurrentCategory(plan.categoryForFileList, focusingOn: movedFile.id)
        selectedFileIDs = [movedFile.id]
        if refreshedTree == nil {
            fileListModel.statusBanner = .changedCategoryTreeRefreshFailed(
                fileID: movedFile.id,
                category: movedFile.category
            )
        } else if fileListModel.errorMapping == nil {
            fileListModel.statusBanner = .changedCategory(fileID: movedFile.id, category: movedFile.category)
        }
    }

    private func refreshedTreeAfterCategoryMove() async -> RepositoryTreeNodeSnapshot? {
        do {
            return try await treeLister.listTree(repoPath: opening.config.repoPath, locale: opening.config.locale)
        } catch {
            return nil
        }
    }
}

struct CategoryMoveRefreshPlan: Equatable {
    var tree: RepositoryTreeNodeSnapshot
    var selectedSidebarID: String
    var focusedFileID: Int64
    var categoryForFileList: String?

    static func make(
        movedFile: FileEntrySnapshot,
        currentSidebarID: String,
        currentTree: RepositoryTreeNodeSnapshot,
        refreshedTree: RepositoryTreeNodeSnapshot?
    ) -> CategoryMoveRefreshPlan {
        let tree = refreshedTree ?? currentTree
        let fallbackSidebarID = sidebarID(forMovedFile: movedFile, in: currentTree) ?? currentSidebarID
        let selectedSidebarID = sidebarID(forMovedFile: movedFile, in: tree) ?? fallbackSidebarID
        let selectedRow = tree.sidebarRow(id: selectedSidebarID) ??
            tree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: tree, depth: 0)
        return CategoryMoveRefreshPlan(
            tree: tree,
            selectedSidebarID: selectedSidebarID,
            focusedFileID: movedFile.id,
            categoryForFileList: selectedRow.categoryForFileList
        )
    }

    private static func sidebarID(forMovedFile file: FileEntrySnapshot,
                                  in tree: RepositoryTreeNodeSnapshot) -> String? {
        tree.sidebarRows.first { row in
            row.categoryForFileList == file.category && row.contains(file)
        }?.id ?? tree.sidebarRows.first { row in
            row.categoryForFileList == file.category && row.pathFilterPrefix == nil
        }?.id
    }
}
