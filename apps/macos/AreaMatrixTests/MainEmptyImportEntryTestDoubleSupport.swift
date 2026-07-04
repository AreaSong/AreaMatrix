@testable import AreaMatrix
import Foundation

struct MainEmptyImportStaticImportPicker: RepositoryImportPicking {
    let urls: [URL]?

    @MainActor
    func chooseImportURLs() -> [URL]? {
        urls
    }
}

typealias CommandPaletteNoopUndoStore = NoopUndoActionStore
