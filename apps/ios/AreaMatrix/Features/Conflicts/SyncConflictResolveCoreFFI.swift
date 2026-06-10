import Carea_matrixFFI
import Foundation

struct SyncConflictResolveCoreFFIClient {
    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategy
    ) throws -> SyncConflictResolutionPreviewReport {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_preview_sync_conflict_resolution(
                try FFIWriter.lowerString(repoPath),
                try FFIWriter.lowerString(conflictID),
                try FFIWriter.lowerResolution(resolution),
                $0
            )
        }
        return try FFIReader.liftPreview(result)
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequest
    ) throws -> SyncConflictResolveReport {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_resolve_sync_conflict(
                try FFIWriter.lowerString(repoPath),
                try FFIWriter.lowerString(conflictID),
                try FFIWriter.lowerRequest(request),
                $0
            )
        }
        return try FFIReader.liftResolve(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_preview_sync_conflict_resolution() == 63696,
              uniffi_area_matrix_core_checksum_func_resolve_sync_conflict() == 50056 else {
            throw SyncConflictEntryError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private func rustCallWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) throws -> RustBuffer)
    throws -> RustBuffer {
    var status = RustCallStatus()
    let result = try callback(&status)
    try checkStatus(status)
    return result
}

private func checkStatus(_ status: RustCallStatus) throws {
    switch status.code {
    case 0:
        return
    case 1:
        throw try FFIReader.liftCoreError(status.errorBuf)
    case 2:
        if status.errorBuf.len > 0 {
            throw try SyncConflictEntryError.unavailable(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw SyncConflictEntryError.unavailable("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw SyncConflictEntryError.unavailable("Unexpected Core call status: \(status.code).")
    }
}

private enum FFIWriter {
    static func lowerString(_ value: String) throws -> RustBuffer {
        try value.utf8CString.withUnsafeBufferPointer { int8Pointer in
            try int8Pointer.withMemoryRebound(to: UInt8.self) { pointer in
                let bytes = UnsafeBufferPointer(rebasing: pointer.prefix(upTo: pointer.count - 1))
                return try lowerBytes(bytes)
            }
        }
    }

    static func lowerResolution(_ resolution: SyncConflictResolutionStrategy) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeResolution(resolution, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    static func lowerRequest(_ request: SyncConflictResolutionRequest) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeResolution(request.strategy, into: &bytes)
        writeString(request.previewToken, into: &bytes)
        writeBool(request.replaceConfirmed, into: &bytes)
        writeOptionalString(request.replaceConfirmationID, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func writeResolution(_ resolution: SyncConflictResolutionStrategy, into bytes: inout [UInt8]) {
        switch resolution {
        case .keepBoth:
            writeInt32(1, into: &bytes)
        case .useExisting:
            writeInt32(2, into: &bytes)
        case .useIncoming:
            writeInt32(3, into: &bytes)
        }
    }

    private static func writeOptionalString(_ value: String?, into bytes: inout [UInt8]) {
        guard let value else {
            bytes.append(0)
            return
        }
        bytes.append(1)
        writeString(value, into: &bytes)
    }

    private static func writeString(_ value: String, into bytes: inout [UInt8]) {
        let valueBytes = Array(value.utf8)
        writeInt32(Int32(valueBytes.count), into: &bytes)
        bytes.append(contentsOf: valueBytes)
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw SyncConflictEntryError.unavailable("Could not lower Core request bytes.")
        }
        return buffer
    }

    private static func writeBool(_ value: Bool, into bytes: inout [UInt8]) {
        bytes.append(value ? 1 : 0)
    }

    private static func writeInt32(_ value: Int32, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}

private enum FFIReader {
    static func liftPreview(_ buffer: RustBuffer) throws -> SyncConflictResolutionPreviewReport {
        var reader = Reader(buffer: buffer)
        let report = try reader.readPreview()
        try reader.finish()
        return report
    }

    static func liftResolve(_ buffer: RustBuffer) throws -> SyncConflictResolveReport {
        var reader = Reader(buffer: buffer)
        let report = try reader.readResolve()
        try reader.finish()
        return report
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> SyncConflictEntryError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: SyncConflictEntryError = switch variant {
        case 1:
            try .io(reader.readString())
        case 2:
            try .database(reader.readString())
        case 6:
            try .conflict(reader.readString())
        case 14:
            try .permissionDenied(reader.readString())
        default:
            try .unavailable(reader.readCoreErrorPayload(variant: variant))
        }
        try reader.finish()
        return error
    }

    static func liftString(_ buffer: RustBuffer) throws -> String {
        defer { try? deallocate(buffer) }
        guard let data = buffer.data else { return "" }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(buffer.len)), as: UTF8.self)
    }

    static func deallocate(_ buffer: RustBuffer) throws {
        var status = RustCallStatus()
        ffi_area_matrix_core_rustbuffer_free(buffer, &status)
        guard status.code == 0 else {
            throw SyncConflictEntryError.unavailable("Could not release Core response buffer.")
        }
    }
}

private struct Reader {
    private let buffer: RustBuffer
    private let data: Data
    private var offset: Data.Index = 0

    init(buffer: RustBuffer) {
        self.buffer = buffer
        if let pointer = buffer.data {
            data = Data(bytes: pointer, count: Int(buffer.len))
        } else {
            data = Data()
        }
    }

    mutating func finish() throws {
        defer { try? FFIReader.deallocate(buffer) }
        guard offset == data.count else {
            throw SyncConflictEntryError.unavailable("Core response buffer contained trailing data.")
        }
    }

    mutating func readPreview() throws -> SyncConflictResolutionPreviewReport {
        try SyncConflictResolutionPreviewReport(
            conflictID: readString(),
            resolution: readResolution(),
            defaultResolution: readResolution(),
            statusAfter: readStatus(),
            versionImpacts: readVersionImpacts(),
            keptPaths: readStrings(),
            retainedPaths: readStrings(),
            plannedTrashPaths: readStrings(),
            affectedFileIDs: readInt64s(),
            canonicalPath: readOptionalString(),
            changeLogAction: readString(),
            destructive: readBool(),
            requiresReplaceConfirmation: readBool(),
            trashRequired: readBool(),
            trashAvailable: readBool(),
            canApply: readBool(),
            blockedReason: readOptionalString(),
            previewToken: readOptionalString(),
            replacePlan: readOptionalReplacePlan()
        )
    }

    mutating func readResolve() throws -> SyncConflictResolveReport {
        try SyncConflictResolveReport(
            conflictID: readString(),
            resolution: readResolution(),
            status: readStatus(),
            keptPaths: readStrings(),
            retainedPaths: readStrings(),
            trashedPaths: readStrings(),
            affectedFileIDs: readInt64s(),
            changeLogAction: readString(),
            undoToken: readOptionalString(),
            resolvedAt: readOptionalInt64()
        )
    }

    mutating func readString() throws -> String {
        let count = try readSequenceCount()
        guard data.count >= offset + count else {
            throw SyncConflictEntryError.unavailable("Core response buffer ended unexpectedly.")
        }
        defer { offset += count }
        return String(decoding: data[offset ..< offset + count], as: UTF8.self)
    }

    mutating func readCoreErrorPayload(variant: Int32) throws -> String {
        switch variant {
        case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
            return try readString()
        default:
            throw SyncConflictEntryError.unavailable("Unexpected Core error variant: \(variant).")
        }
    }

    private mutating func readVersionImpacts() throws -> [SyncConflictVersionImpact] {
        let count = try readSequenceCount()
        var impacts: [SyncConflictVersionImpact] = []
        impacts.reserveCapacity(count)
        for _ in 0 ..< count {
            try impacts.append(SyncConflictVersionImpact(
                path: readString(),
                fileID: readOptionalInt64(),
                role: readFileRole(),
                willKeep: readBool(),
                willBeCanonical: readBool(),
                willRemainUserVisible: readBool(),
                willMoveToTrash: readBool(),
                recoveryTarget: readOptionalString(),
                reason: readOptionalString()
            ))
        }
        return impacts
    }

    private mutating func readOptionalReplacePlan() throws -> SyncConflictReplacePlan? {
        let tag = try readInt8()
        switch tag {
        case 0:
            return nil
        case 1:
            return try SyncConflictReplacePlan(
                oldPath: readString(),
                newPath: readString(),
                oldHashSha256: readOptionalString(),
                newHashSha256: readOptionalString(),
                affectedFileID: readOptionalInt64(),
                backupTarget: readOptionalString(),
                databaseUpdate: readString(),
                changeLogAction: readString(),
                recoveryNote: readString()
            )
        default:
            throw SyncConflictEntryError.unavailable("Unexpected replace plan tag: \(tag).")
        }
    }

    private mutating func readStrings() throws -> [String] {
        let count = try readSequenceCount()
        var values: [String] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            try values.append(readString())
        }
        return values
    }

    private mutating func readInt64s() throws -> [Int64] {
        let count = try readSequenceCount()
        var values: [Int64] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            try values.append(readInt64())
        }
        return values
    }

    private mutating func readOptionalString() throws -> String? {
        let tag = try readInt8()
        switch tag {
        case 0:
            return nil
        case 1:
            return try readString()
        default:
            throw SyncConflictEntryError.unavailable("Unexpected optional string tag: \(tag).")
        }
    }

    private mutating func readOptionalInt64() throws -> Int64? {
        let tag = try readInt8()
        switch tag {
        case 0:
            return nil
        case 1:
            return try readInt64()
        default:
            throw SyncConflictEntryError.unavailable("Unexpected optional integer tag: \(tag).")
        }
    }

    private mutating func readStatus() throws -> SyncConflictEntryStatus {
        switch try readInt32() {
        case 1:
            return .needsReview
        case 2:
            return .resolved
        case let value:
            throw SyncConflictEntryError.unavailable("Unexpected sync conflict status: \(value).")
        }
    }

    private mutating func readResolution() throws -> SyncConflictResolutionStrategy {
        switch try readInt32() {
        case 1:
            return .keepBoth
        case 2:
            return .useExisting
        case 3:
            return .useIncoming
        case let value:
            throw SyncConflictEntryError.unavailable("Unexpected sync conflict resolution: \(value).")
        }
    }

    private mutating func readFileRole() throws -> SyncConflictEntryFileRole {
        switch try readInt32() {
        case 1:
            return .existing
        case 2:
            return .incoming
        case 3:
            return .conflictCopy
        case 4:
            return .missing
        case 5:
            return .unknown
        case let value:
            throw SyncConflictEntryError.unavailable("Unexpected sync conflict file role: \(value).")
        }
    }

    private mutating func readSequenceCount() throws -> Int {
        let count = Int(try readInt32())
        guard count >= 0 else {
            throw SyncConflictEntryError.unavailable("Core response sequence length is invalid.")
        }
        return count
    }

    private mutating func readBool() throws -> Bool {
        try readInt8() != 0
    }

    private mutating func readInt8() throws -> Int8 {
        guard data.count >= offset + 1 else {
            throw SyncConflictEntryError.unavailable("Core response buffer ended unexpectedly.")
        }
        defer { offset += 1 }
        return Int8(bitPattern: data[offset])
    }

    mutating func readInt32() throws -> Int32 {
        guard data.count >= offset + 4 else {
            throw SyncConflictEntryError.unavailable("Core response buffer ended unexpectedly.")
        }
        defer { offset += 4 }
        var value: Int32 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
        return value.bigEndian
    }

    private mutating func readInt64() throws -> Int64 {
        guard data.count >= offset + 8 else {
            throw SyncConflictEntryError.unavailable("Core response buffer ended unexpectedly.")
        }
        defer { offset += 8 }
        var value: Int64 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
        return value.bigEndian
    }
}
