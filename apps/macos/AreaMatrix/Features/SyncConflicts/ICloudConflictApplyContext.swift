import Foundation

struct ICloudConflictApplyContext {
    var fileID: Int64
    var result: ICloudConflictApplyResult
    var originalPath: String?
    var conflictedCopyPath: String?
}
