import Carea_matrixFFI
import Foundation

struct MissingFileRecoveryCoreFFIClient {
    func getMissingFileState(repoPath: String, fileID: Int64) throws -> MissingFileRecoveryState {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_get_missing_file_state(path, fileID, $0)
        }
        return try FFIReader.liftState(result)
    }

    func relinkMissingFile(
        repoPath: String,
        request: MissingFileRelinkRequest
    ) throws -> MissingFileRecoveryReport {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let loweredRequest = try FFIWriter.lowerRelinkRequest(request)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_relink_missing_file(path, loweredRequest, $0)
        }
        return try FFIReader.liftReport(result)
    }

    func removeMissingFileRecord(
        repoPath: String,
        request: MissingFileRemoveRecordRequest
    ) throws -> MissingFileRecoveryReport {
        try ensureCurrentContract()
        let path = try FFIWriter.lowerString(repoPath)
        let loweredRequest = try FFIWriter.lowerRemoveRecordRequest(request)
        let result = try rustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_remove_missing_file_record(path, loweredRequest, $0)
        }
        return try FFIReader.liftReport(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_get_missing_file_state() == 9097,
              uniffi_area_matrix_core_checksum_func_relink_missing_file() == 39194,
              uniffi_area_matrix_core_checksum_func_remove_missing_file_record() == 46697 else {
            throw MissingFileRecoveryError.unavailable("AreaMatrix Core binding contract mismatch.")
        }
    }
}

private enum MissingFileRecoveryCoreFFIError: LocalizedError {
    case bufferOverflow
    case unexpectedStatus(Int8)
    case unexpectedEnumCase(Int64)
    case unexpectedOptionalTag(Int8)
    case incompleteData
    case invalidStringEncoding
    case rustPanic(String)

    var errorDescription: String? {
        switch self {
        case .bufferOverflow:
            "Core response buffer ended unexpectedly."
        case let .unexpectedStatus(code):
            "Unexpected Core call status: \(code)."
        case let .unexpectedEnumCase(value):
            "Unexpected Core enum value: \(value)."
        case let .unexpectedOptionalTag(tag):
            "Unexpected Core optional tag: \(tag)."
        case .incompleteData:
            "Core response buffer contained trailing data."
        case .invalidStringEncoding:
            "Core response buffer contained invalid UTF-8."
        case let .rustPanic(message):
            message
        }
    }
}

private func rustCallWithCoreError(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> RustBuffer)
    throws -> RustBuffer {
    var status = RustCallStatus()
    let result = callback(&status)
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
            throw try MissingFileRecoveryCoreFFIError.rustPanic(FFIReader.liftString(status.errorBuf))
        }
        try FFIReader.deallocate(status.errorBuf)
        throw MissingFileRecoveryCoreFFIError.rustPanic("Rust panic")
    default:
        try FFIReader.deallocate(status.errorBuf)
        throw MissingFileRecoveryCoreFFIError.unexpectedStatus(status.code)
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

    static func lowerRelinkRequest(_ request: MissingFileRelinkRequest) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt64(request.fileID, into: &bytes)
        writeString(request.newPath, into: &bytes)
        writeBool(request.confirmed, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    static func lowerRemoveRecordRequest(_ request: MissingFileRemoveRecordRequest) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt64(request.fileID, into: &bytes)
        writeBool(request.confirmed, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw MissingFileRecoveryCoreFFIError.unexpectedStatus(status.code)
        }
        return buffer
    }

    private static func writeString(_ value: String, into bytes: inout [UInt8]) {
        let data = Array(value.utf8)
        writeInt32(Int32(data.count), into: &bytes)
        bytes.append(contentsOf: data)
    }

    private static func writeBool(_ value: Bool, into bytes: inout [UInt8]) {
        bytes.append(value ? 1 : 0)
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
    static func liftState(_ buffer: RustBuffer) throws -> MissingFileRecoveryState {
        var reader = Reader(buffer: buffer)
        let state = try reader.readState()
        try reader.finish()
        return state
    }

    static func liftReport(_ buffer: RustBuffer) throws -> MissingFileRecoveryReport {
        var reader = Reader(buffer: buffer)
        let report = try reader.readReport()
        try reader.finish()
        return report
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> MissingFileRecoveryError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: MissingFileRecoveryError = switch variant {
        case 2:
            try .database(reader.readString())
        case 8:
            try .fileNotFound(reader.readString())
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
        let bytes = UnsafeBufferPointer(start: data, count: Int(buffer.len))
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw MissingFileRecoveryCoreFFIError.invalidStringEncoding
        }
        return string
    }

    static func deallocate(_ buffer: RustBuffer) throws {
        var status = RustCallStatus()
        ffi_area_matrix_core_rustbuffer_free(buffer, &status)
        guard status.code == 0 else {
            throw MissingFileRecoveryCoreFFIError.unexpectedStatus(status.code)
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
                throw MissingFileRecoveryCoreFFIError.incompleteData
            }
        }

        mutating func readState() throws -> MissingFileRecoveryState {
            try MissingFileRecoveryState(
                fileID: readInt64(),
                relativePath: readString(),
                lastKnownPath: readOptionalString(),
                lastSeenAt: readOptionalInt64(),
                reason: readReason(),
                expectedHashSha256: readOptionalString(),
                canLocate: readBool(),
                canTryAgain: readBool(),
                canRemoveRecord: readBool(),
                removeRecordRequiresConfirmation: readBool(),
                canRunRescan: readBool(),
                rescanDisabledReason: readOptionalString()
            )
        }

        mutating func readReport() throws -> MissingFileRecoveryReport {
            try MissingFileRecoveryReport(
                fileID: readInt64(),
                status: readRecoveryStatus(),
                previousPath: readOptionalString(),
                currentPath: readOptionalString(),
                hashMatched: readBool(),
                recordRemoved: readBool(),
                fileDeleted: readBool(),
                changeLogAction: readOptionalString(),
                message: readOptionalString()
            )
        }

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw MissingFileRecoveryCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            guard let string = String(bytes: data[offset ..< offset + count], encoding: .utf8) else {
                throw MissingFileRecoveryCoreFFIError.invalidStringEncoding
            }
            return string
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw MissingFileRecoveryCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw MissingFileRecoveryCoreFFIError.unexpectedEnumCase(Int64(variant))
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
                throw MissingFileRecoveryCoreFFIError.unexpectedOptionalTag(tag)
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
                throw MissingFileRecoveryCoreFFIError.unexpectedOptionalTag(tag)
            }
        }

        private mutating func readReason() throws -> MissingFileReason {
            switch try readInt32() {
            case 1:
                return .pathMissing
            case 2:
                return .permissionDenied
            case 3:
                return .cloudPlaceholder
            case 4:
                return .externalVolumeDisconnected
            case 5:
                return .unknown
            case let value:
                throw MissingFileRecoveryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readRecoveryStatus() throws -> MissingFileRecoveryStatus {
            switch try readInt32() {
            case 1:
                return .missing
            case 2:
                return .present
            case 3:
                return .relinked
            case 4:
                return .hashMismatch
            case 5:
                return .recordRemoved
            case 6:
                return .blocked
            case let value:
                throw MissingFileRecoveryCoreFFIError.unexpectedEnumCase(Int64(value))
            }
        }

        private mutating func readBool() throws -> Bool {
            try readInt8() != 0
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw MissingFileRecoveryCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        private mutating func readInt64() throws -> Int64 {
            guard data.count >= offset + 8 else {
                throw MissingFileRecoveryCoreFFIError.bufferOverflow
            }
            defer { offset += 8 }
            var value: Int64 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 8) }
            return value.bigEndian
        }
    }
}
