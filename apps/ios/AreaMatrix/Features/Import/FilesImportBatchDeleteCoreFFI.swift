import Carea_matrixFFI
import CryptoKit
import Foundation

struct FilesImportBatchDeletePreviewItem {
    var fileID: Int64
    var willMoveToTrash: Bool
    var status: FilesImportBatchDeletePreviewStatus
    var reason: String?
}

enum FilesImportBatchDeletePreviewStatus {
    case willMoveToTrash
    case indexOnly
    case missing
    case skipped
    case blocked
}

struct FilesImportBatchDeletePreviewReport {
    var previewToken: String
    var trashAvailable: Bool
    var undoAvailable: Bool
    var canApply: Bool
    var applyBlockedReason: String?
    var items: [FilesImportBatchDeletePreviewItem]

    func blockedReason(for item: FilesImportBatchDeletePreviewItem?) -> String {
        if !trashAvailable {
            return "Replace requires system Trash."
        }
        if let applyBlockedReason, !applyBlockedReason.isEmpty {
            return applyBlockedReason
        }
        if let itemReason = item?.reason, !itemReason.isEmpty {
            return itemReason
        }
        return "Core delete preflight did not approve this replace."
    }
}

struct FilesImportBatchDeleteReport {
    var movedToTrashCount: Int64
    var failedCount: Int64
    var itemResults: [FilesImportBatchDeleteItemResult]
    var affectedFileIDs: [Int64]
    var undoToken: String?

    var failureSummary: String {
        itemResults.compactMap(\.error).first ?? "Core could not move the existing file to Trash."
    }
}

struct FilesImportBatchDeleteItemResult {
    var error: String?
}

struct FilesImportBatchDeleteFFIClient {
    func previewBatchDelete(repoPath: String, fileID: Int64) throws -> FilesImportBatchDeletePreviewReport {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_preview_batch_delete(
                try FFIWriter.lowerString(repoPath),
                try FFIWriter.lowerFileIDs([fileID]),
                try FFIWriter.lowerMoveToTrashMode(),
                $0
            )
        }
        return try FFIReader.liftPreview(result)
    }

    func batchDeleteToTrash(repoPath: String, fileID: Int64, previewToken: String) throws
        -> FilesImportBatchDeleteReport {
        try ensureCurrentContract()
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_batch_delete_to_trash(
                try FFIWriter.lowerString(repoPath),
                try FFIWriter.lowerFileIDs([fileID]),
                try FFIWriter.lowerMoveToTrashMode(),
                try FFIWriter.lowerString(previewToken),
                $0
            )
        }
        return try FFIReader.liftDelete(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_preview_batch_delete() == 58527,
              uniffi_area_matrix_core_checksum_func_batch_delete_to_trash() == 63655 else {
            throw FilesImportError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

enum SHA256FileHasher {
    static func hash(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
            throw try FilesImportError.unavailable(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw FilesImportError.unavailable("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw FilesImportError.unavailable("Unexpected Core call status: \(status.code).")
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

    static func lowerFileIDs(_ fileIDs: [Int64]) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(Int32(fileIDs.count), into: &bytes)
        for fileID in fileIDs {
            writeInt64(fileID, into: &bytes)
        }
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    static func lowerMoveToTrashMode() throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(1, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw FilesImportError.unavailable("Could not lower Core request bytes.")
        }
        return buffer
    }

    private static func writeInt32(_ value: Int32, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }

    private static func writeInt64(_ value: Int64, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}

private enum FFIReader {
    static func liftPreview(_ buffer: RustBuffer) throws -> FilesImportBatchDeletePreviewReport {
        var reader = Reader(buffer: buffer)
        let report = try reader.readPreviewReport()
        try reader.finish()
        return report
    }

    static func liftDelete(_ buffer: RustBuffer) throws -> FilesImportBatchDeleteReport {
        var reader = Reader(buffer: buffer)
        let report = try reader.readDeleteReport()
        try reader.finish()
        return report
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> FilesImportError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: FilesImportError = switch variant {
        case 1:
            try .unreadableFile(reader.readString())
        case 2:
            try .database(reader.readString())
        case 6:
            try .nameConflict(reader.readString())
        case 7:
            try .duplicateContent(reader.readString())
        case 8:
            try .unavailable(reader.readString())
        case 11:
            try .invalidPath(reader.readString())
        case 12:
            try .iCloudPlaceholder(reader.readString())
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
            throw FilesImportError.unavailable("Could not release Core response buffer.")
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
                throw FilesImportError.unavailable("Core response buffer contained trailing data.")
            }
        }

        mutating func readPreviewReport() throws -> FilesImportBatchDeletePreviewReport {
            _ = try readInt64()
            _ = try readBatchDeleteMode()
            let token = try readString()
            let trashAvailable = try readBool()
            let undoAvailable = try readBool()
            try skipDeleteCounts()
            let items = try readPreviewItems()
            let canApply = try readBool()
            let blockedReason = try readOptionalString()
            return FilesImportBatchDeletePreviewReport(
                previewToken: token,
                trashAvailable: trashAvailable,
                undoAvailable: undoAvailable,
                canApply: canApply,
                applyBlockedReason: blockedReason,
                items: items
            )
        }

        mutating func readDeleteReport() throws -> FilesImportBatchDeleteReport {
            _ = try readInt64()
            _ = try readBatchDeleteMode()
            let moved = try readInt64()
            _ = try readInt64()
            _ = try readInt64()
            let failed = try readInt64()
            let results = try readDeleteItemResults()
            let affected = try readInt64Sequence()
            let undoToken = try readOptionalString()
            return FilesImportBatchDeleteReport(
                movedToTrashCount: moved,
                failedCount: failed,
                itemResults: results,
                affectedFileIDs: affected,
                undoToken: undoToken
            )
        }

        private mutating func skipDeleteCounts() throws {
            for _ in 0 ..< 5 {
                _ = try readInt64()
            }
        }

        private mutating func readPreviewItems() throws -> [FilesImportBatchDeletePreviewItem] {
            let count = try readSequenceCount()
            var items: [FilesImportBatchDeletePreviewItem] = []
            items.reserveCapacity(count)
            for _ in 0 ..< count {
                items.append(try readPreviewItem())
            }
            return items
        }

        private mutating func readPreviewItem() throws -> FilesImportBatchDeletePreviewItem {
            let fileID = try readInt64()
            _ = try readOptionalString()
            _ = try readOptionalString()
            _ = try readOptionalStorageMode()
            _ = try readBatchDeleteMode()
            let willMoveToTrash = try readBool()
            _ = try readBool()
            let status = try readPreviewStatus()
            let reason = try readOptionalString()
            return FilesImportBatchDeletePreviewItem(
                fileID: fileID,
                willMoveToTrash: willMoveToTrash,
                status: status,
                reason: reason
            )
        }

        private mutating func readDeleteItemResults() throws -> [FilesImportBatchDeleteItemResult] {
            let count = try readSequenceCount()
            var results: [FilesImportBatchDeleteItemResult] = []
            results.reserveCapacity(count)
            for _ in 0 ..< count {
                _ = try readInt64()
                _ = try readOptionalString()
                _ = try readDeleteResultStatus()
                results.append(FilesImportBatchDeleteItemResult(error: try readOptionalString()))
            }
            return results
        }

        private mutating func readInt64Sequence() throws -> [Int64] {
            let count = try readSequenceCount()
            var values: [Int64] = []
            values.reserveCapacity(count)
            for _ in 0 ..< count {
                try values.append(readInt64())
            }
            return values
        }

        mutating func readString() throws -> String {
            let count = try readSequenceCount()
            guard data.count >= offset + count else {
                throw FilesImportError.unavailable("Core response buffer ended unexpectedly.")
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw FilesImportError.unavailable("Unexpected Core error variant: \(variant).")
            }
        }

        private mutating func readOptionalString() throws -> String? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readString()
            default:
                throw FilesImportError.unavailable("Unexpected optional string tag: \(tag).")
            }
        }

        private mutating func readOptionalStorageMode() throws -> String? {
            let tag = try readInt8()
            switch tag {
            case 0:
                return nil
            case 1:
                return try readStorageMode()
            default:
                throw FilesImportError.unavailable("Unexpected optional storage mode tag: \(tag).")
            }
        }

        private mutating func readStorageMode() throws -> String {
            switch try readInt32() {
            case 1:
                return "Moved"
            case 2:
                return "Copied"
            case 3:
                return "Indexed"
            case let value:
                throw FilesImportError.unavailable("Unexpected storage mode: \(value).")
            }
        }

        private mutating func readBatchDeleteMode() throws -> String {
            switch try readInt32() {
            case 1:
                return "MoveToTrash"
            case 2:
                return "RemoveFromIndex"
            case let value:
                throw FilesImportError.unavailable("Unexpected delete mode: \(value).")
            }
        }

        private mutating func readPreviewStatus() throws -> FilesImportBatchDeletePreviewStatus {
            switch try readInt32() {
            case 1:
                return .willMoveToTrash
            case 2:
                return .indexOnly
            case 3:
                return .missing
            case 4:
                return .skipped
            case 5:
                return .blocked
            case let value:
                throw FilesImportError.unavailable("Unexpected delete preview status: \(value).")
            }
        }

        private mutating func readDeleteResultStatus() throws -> String {
            switch try readInt32() {
            case 1:
                return "MovedToTrash"
            case 2:
                return "RemovedFromIndex"
            case 3:
                return "Skipped"
            case 4:
                return "Failed"
            case let value:
                throw FilesImportError.unavailable("Unexpected delete result status: \(value).")
            }
        }

        private mutating func readSequenceCount() throws -> Int {
            let count = Int(try readInt32())
            guard count >= 0 else {
                throw FilesImportError.unavailable("Core response sequence length is invalid.")
            }
            return count
        }

        private mutating func readBool() throws -> Bool {
            try readInt8() != 0
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw FilesImportError.unavailable("Core response buffer ended unexpectedly.")
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw FilesImportError.unavailable("Core response buffer ended unexpectedly.")
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        private mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw FilesImportError.unavailable("Core response buffer ended unexpectedly.")
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }
    }
}
