import Foundation

extension MainFileListModel {
    func noteWriteBlock(for file: FileEntrySnapshot) -> MainDetailNoteWriteBlock? {
        if isReadOnly { return .repoReadOnly }
        if file.availability == .missing { return .fileMissing }
        if writeLockedFileIDs.contains(file.id) { return .importLocked }
        if isLoading { return .listLoading }
        return nil
    }
}
