import Carea_matrixFFI
import Foundation

struct MobileCloudStorageCoreFFIClient: Sendable {
    func detectCloudStorageState(repoPath: String) throws -> MobileCloudStorageState {
        try ensureCurrentContract()
        let path = try CloudFFIWriter.lowerString(repoPath)
        let result = try cloudRustCallWithCoreError {
            uniffi_area_matrix_core_fn_func_detect_cloud_storage_state(path, $0)
        }
        return try CloudFFIReader.liftCloudStorageState(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_detect_cloud_storage_state() == 18169 else {
            throw MobileRepositoryConnectionError.unavailable("AreaMatrix Core cloud binding contract mismatch.")
        }
    }
}

private enum MobileCloudStorageCoreFFIError: LocalizedError {
    case bufferOverflow
    case unexpectedStatus(Int8)
    case unexpectedEnumCase(Int32)
    case incompleteData
    case rustPanic(String)

    var errorDescription: String? {
        switch self {
        case .bufferOverflow:
            "Core cloud response buffer ended unexpectedly."
        case let .unexpectedStatus(code):
            "Unexpected Core cloud call status: \(code)."
        case let .unexpectedEnumCase(value):
            "Unexpected Core cloud enum value: \(value)."
        case .incompleteData:
            "Core cloud response buffer contained trailing data."
        case let .rustPanic(message):
            message
        }
    }
}

private func cloudRustCallWithCoreError(
    _ callback: (UnsafeMutablePointer<RustCallStatus>) -> RustBuffer
) throws -> RustBuffer {
    var status = RustCallStatus()
    let result = callback(&status)
    try checkCloudStatus(status)
    return result
}

private func checkCloudStatus(_ status: RustCallStatus) throws {
    switch status.code {
    case 0:
        return
    case 1:
        throw try CloudFFIReader.liftCoreError(status.errorBuf)
    case 2:
        if status.errorBuf.len > 0 {
            throw try MobileCloudStorageCoreFFIError.rustPanic(CloudFFIReader.liftString(status.errorBuf))
        }
        try CloudFFIReader.deallocate(status.errorBuf)
        throw MobileCloudStorageCoreFFIError.rustPanic("Rust panic")
    default:
        try CloudFFIReader.deallocate(status.errorBuf)
        throw MobileCloudStorageCoreFFIError.unexpectedStatus(status.code)
    }
}

private enum CloudFFIWriter {
    static func lowerString(_ value: String) throws -> RustBuffer {
        try value.utf8CString.withUnsafeBufferPointer { int8Pointer in
            try int8Pointer.withMemoryRebound(to: UInt8.self) { pointer in
                let bytes = UnsafeBufferPointer(rebasing: pointer.prefix(upTo: pointer.count - 1))
                return try lowerBytes(bytes)
            }
        }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw MobileCloudStorageCoreFFIError.unexpectedStatus(status.code)
        }
        return buffer
    }
}

private enum CloudFFIReader {
    static func liftCloudStorageState(_ buffer: RustBuffer) throws -> MobileCloudStorageState {
        var reader = Reader(buffer: buffer)
        let state = try MobileCloudStorageState(
            repoPath: reader.readString(),
            providerKind: reader.readProviderKind(),
            risk: reader.readRiskLevel(),
            placeholderState: reader.readPlaceholderState(),
            permissionState: reader.readPermissionState(),
            statusSummary: reader.readString(),
            riskReasons: reader.readStringList(),
            recommendedAction: reader.readRecommendedAction(),
            requiresNoticeAcknowledgement: reader.readBool(),
            noticeAcknowledged: reader.readBool(),
            canRetry: reader.readBool(),
            requiresReconnect: reader.readBool()
        )
        try reader.finish()
        return state
    }

    static func liftCoreError(_ buffer: RustBuffer) throws -> MobileRepositoryConnectionError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let error: MobileRepositoryConnectionError
        switch variant {
        case 3:
            error = try .invalidRepository(reader.readString())
        case 10, 11:
            error = try .invalidPath(reader.readString())
        case 12:
            error = try .iCloudPlaceholder(reader.readString())
        case 14:
            error = try .permissionDenied(reader.readString())
        default:
            error = try .unavailable(reader.readCoreErrorPayload(variant: variant))
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
            throw MobileCloudStorageCoreFFIError.unexpectedStatus(status.code)
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
            defer { try? CloudFFIReader.deallocate(buffer) }
            guard offset == data.count else {
                throw MobileCloudStorageCoreFFIError.incompleteData
            }
        }

        mutating func readString() throws -> String {
            let count = Int(try readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw MobileCloudStorageCoreFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readStringList() throws -> [String] {
            let count = Int(try readInt32())
            guard count >= 0 else {
                throw MobileCloudStorageCoreFFIError.bufferOverflow
            }
            var values: [String] = []
            values.reserveCapacity(count)
            for _ in 0 ..< count {
                values.append(try readString())
            }
            return values
        }

        mutating func readBool() throws -> Bool {
            try readInt8() != 0
        }

        mutating func readProviderKind() throws -> MobileCloudStorageProviderKind {
            switch try readInt32() {
            case 1:
                return .local
            case 2:
                return .iCloudDrive
            case 3:
                return .oneDrive
            case 4:
                return .unknown
            case let value:
                throw MobileCloudStorageCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readRiskLevel() throws -> MobileCloudStorageRiskLevel {
            switch try readInt32() {
            case 1:
                return .noRisk
            case 2:
                return .low
            case 3:
                return .medium
            case 4:
                return .high
            case 5:
                return .unknown
            case let value:
                throw MobileCloudStorageCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readPlaceholderState() throws -> MobileCloudPlaceholderState {
            switch try readInt32() {
            case 1:
                return .notPlaceholder
            case 2:
                return .placeholder
            case 3:
                return .unknown
            case let value:
                throw MobileCloudStorageCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readPermissionState() throws -> MobileCloudPermissionState {
            switch try readInt32() {
            case 1:
                return .accessible
            case 2:
                return .permissionDenied
            case 3:
                return .accessExpired
            case 4:
                return .unknown
            case let value:
                throw MobileCloudStorageCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readRecommendedAction() throws -> MobileCloudStorageRecommendedAction {
            switch try readInt32() {
            case 1:
                return .none
            case 2:
                return .acknowledgeNotice
            case 3:
                return .retryStatusCheck
            case 4:
                return .reconnectFolder
            case 5:
                return .chooseLocalFolder
            case let value:
                throw MobileCloudStorageCoreFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readCoreErrorPayload(variant: Int32) throws -> String {
            switch variant {
            case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
                return try readString()
            default:
                throw MobileCloudStorageCoreFFIError.unexpectedEnumCase(variant)
            }
        }

        private mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw MobileCloudStorageCoreFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw MobileCloudStorageCoreFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }
    }
}
