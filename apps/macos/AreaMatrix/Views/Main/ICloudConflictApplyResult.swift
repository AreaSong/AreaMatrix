import Foundation

struct ICloudConflictApplyResult {
    var strategy: ICloudConflictResolutionStrategy
    var report: ICloudConflictResolveReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}
