import SwiftUI

extension MainRepositoryContentView {
    func openImportFromCommandPalette() {
        closeCommandPalette()
        onImport()
    }

    func openSettingsFromCommandPalette() {
        closeCommandPalette()
        onOpenSettings()
    }

    func beginSearchFromCommandPalette() {
        closeCommandPalette()
        beginCommandFindSearch()
    }

    func openBatchAddTagsFromCommandPalette() {
        let route = commandPaletteBatchAddTagsRoute()
        pendingBatchAddTagsRoute = route
        closeCommandPalette()
    }

    func openBatchChangeCategoryFromCommandPalette() {
        let route = commandPaletteBatchChangeCategoryRoute()
        pendingBatchChangeCategoryRoute = route
        closeCommandPalette()
    }

    func openBatchDeleteFromCommandPalette() {
        pendingBatchDeleteRoute = commandPaletteBatchDeleteRoute()
        closeCommandPalette()
    }

    func openBatchRenameFromCommandPalette() {
        pendingBatchRenameRoute = commandPaletteBatchRenameRoute()
        closeCommandPalette()
    }

    func focusFileFromCommandPalette(_ fileID: Int64) {
        selectedFileIDs = [fileID]
        closeCommandPalette()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    func openRepositoryFromCommandPalette() {
        closeCommandPalette()
        onOpenRepository()
    }

    func openHelpFromCommandPalette() {
        closeCommandPalette()
        onOpenHelp()
    }

    func openClassifierRuleEditorFromCommandPalette() {
        fileListModel.clearCommandPaletteState()
        fileListModel.commandPaletteQuery = ""
        fileListModel.pendingSearchDestination = .classifierRuleEditor(context: nil)
    }
}
