import Carea_matrixFFI
import Foundation

protocol PlatformDifferencesCapabilityLoading: Sendable {
    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) async throws -> PlatformDifferencesCapabilities
}

enum PlatformDifferencesPlatformId: String, Equatable, Sendable {
    case macos = "macOS"
    case ios = "iOS"
    case windows = "Windows"
    case linux = "Linux"
    case unknown = "Unknown"
}

enum PlatformDifferencesCapabilityStatus: String, Equatable, Sendable {
    case available = "Available"
    case limited = "Limited"
    case notAvailable = "Not available"
    case unknown = "Unknown"
}

struct PlatformDifferencesCapabilitySupport: Equatable, Sendable {
    var status: PlatformDifferencesCapabilityStatus
    var uiEnabled: Bool
    var requiresPermission: Bool
    var reason: String?
}

struct PlatformDifferencesCapabilities: Equatable, Sendable {
    var platform: PlatformDifferencesPlatformId
    var appVersion: String
    var watcher: PlatformDifferencesCapabilitySupport
    var trash: PlatformDifferencesCapabilitySupport
    var shareExtension: PlatformDifferencesCapabilitySupport
    var cloudPlaceholder: PlatformDifferencesCapabilitySupport
    var securityBookmark: PlatformDifferencesCapabilitySupport
}

enum PlatformDifferencesCapabilityError: Error, Equatable, LocalizedError {
    case config(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .config(reason):
            reason
        case let .unavailable(message):
            message
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .config:
            "Use a supported platform id and app version, then retry."
        case .unavailable:
            "Check the Core bridge integration, then retry."
        }
    }
}

actor LivePlatformDifferencesCapabilityBridge: PlatformDifferencesCapabilityLoading {
    private let client: PlatformDifferencesCapabilitiesFFIClient

    init(client: PlatformDifferencesCapabilitiesFFIClient = PlatformDifferencesCapabilitiesFFIClient()) {
        self.client = client
    }

    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) async throws -> PlatformDifferencesCapabilities {
        try client.getPlatformCapabilities(platform: platform, appVersion: appVersion)
    }
}

struct PlatformDifferencesCapabilitiesFFIClient: Sendable {
    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) throws -> PlatformDifferencesCapabilities {
        try ensureCurrentContract()
        let result = try platformCapabilityRustCall {
            uniffi_area_matrix_core_fn_func_get_platform_capabilities(
                try PlatformCapabilityFFIWriter.lowerPlatformId(platform),
                try PlatformCapabilityFFIWriter.lowerString(appVersion),
                $0
            )
        }
        return try PlatformCapabilityFFIReader.liftCapabilities(result)
    }

    private func ensureCurrentContract() throws {
        guard ffi_area_matrix_core_uniffi_contract_version() == 26,
              uniffi_area_matrix_core_checksum_func_get_platform_capabilities() == 42907 else {
            throw PlatformDifferencesCapabilityError.unavailable(
                "AreaMatrix Core platform capability binding mismatch."
            )
        }
    }
}

private enum PlatformCapabilityFFIError: LocalizedError {
    case bufferOverflow
    case incompleteData
    case rustPanic(String)
    case unexpectedEnumCase(Int32)
    case unexpectedOptionalTag(Int8)
    case unexpectedStatus(Int8)

    var errorDescription: String? {
        switch self {
        case .bufferOverflow:
            "Core capability buffer ended unexpectedly."
        case .incompleteData:
            "Core capability buffer contained trailing data."
        case let .rustPanic(message):
            message
        case let .unexpectedEnumCase(value):
            "Unexpected Core capability enum value: \(value)."
        case let .unexpectedOptionalTag(tag):
            "Unexpected Core optional tag: \(tag)."
        case let .unexpectedStatus(code):
            "Unexpected Core call status: \(code)."
        }
    }
}

private func platformCapabilityRustCall(
    _ callback: (UnsafeMutablePointer<RustCallStatus>) throws -> RustBuffer
) throws -> RustBuffer {
    var status = RustCallStatus()
    let result = try callback(&status)
    try PlatformCapabilityFFIReader.checkStatus(status)
    return result
}

private enum PlatformCapabilityFFIWriter {
    static func lowerPlatformId(_ platform: PlatformDifferencesPlatformId) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(platform.coreEnumTag, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    static func lowerString(_ value: String) throws -> RustBuffer {
        let bytes = Array(value.utf8)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw PlatformCapabilityFFIError.unexpectedStatus(status.code)
        }
        return buffer
    }

    private static func writeInt32(_ value: Int32, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}

private enum PlatformCapabilityFFIReader {
    static func checkStatus(_ status: RustCallStatus) throws {
        switch status.code {
        case 0:
            return
        case 1:
            throw try liftCoreError(status.errorBuf)
        case 2:
            if status.errorBuf.len > 0 {
                throw try PlatformCapabilityFFIError.rustPanic(liftString(status.errorBuf))
            }
            try deallocate(status.errorBuf)
            throw PlatformCapabilityFFIError.rustPanic("Rust panic")
        default:
            try deallocate(status.errorBuf)
            throw PlatformCapabilityFFIError.unexpectedStatus(status.code)
        }
    }

    static func liftCapabilities(_ buffer: RustBuffer) throws -> PlatformDifferencesCapabilities {
        var reader = Reader(buffer: buffer)
        let capabilities = try reader.readCapabilities()
        try reader.finish()
        return capabilities
    }

    private static func liftCoreError(_ buffer: RustBuffer) throws -> PlatformDifferencesCapabilityError {
        var reader = Reader(buffer: buffer)
        let variant = try reader.readInt32()
        let payload = try reader.readString()
        try reader.finish()
        return variant == 3 ? .config(payload) : .unavailable(payload)
    }

    private static func liftString(_ buffer: RustBuffer) throws -> String {
        defer { try? deallocate(buffer) }
        guard let data = buffer.data else { return "" }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(buffer.len)), as: UTF8.self)
    }

    private static func deallocate(_ buffer: RustBuffer) throws {
        var status = RustCallStatus()
        ffi_area_matrix_core_rustbuffer_free(buffer, &status)
        guard status.code == 0 else {
            throw PlatformCapabilityFFIError.unexpectedStatus(status.code)
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
            defer { try? PlatformCapabilityFFIReader.deallocate(buffer) }
            guard offset == data.count else {
                throw PlatformCapabilityFFIError.incompleteData
            }
        }

        mutating func readCapabilities() throws -> PlatformDifferencesCapabilities {
            try PlatformDifferencesCapabilities(
                platform: readPlatformId(),
                appVersion: readString(),
                watcher: readSupport(),
                trash: readSupport(),
                shareExtension: readSupport(),
                cloudPlaceholder: readSupport(),
                securityBookmark: readSupport()
            )
        }

        mutating func readSupport() throws -> PlatformDifferencesCapabilitySupport {
            try PlatformDifferencesCapabilitySupport(
                status: readCapabilityStatus(),
                uiEnabled: readBool(),
                requiresPermission: readBool(),
                reason: readOptionalString()
            )
        }

        mutating func readPlatformId() throws -> PlatformDifferencesPlatformId {
            switch try readInt32() {
            case 1:
                return .macos
            case 2:
                return .ios
            case 3:
                return .windows
            case 4:
                return .linux
            case 5:
                return .unknown
            case let value:
                throw PlatformCapabilityFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readCapabilityStatus() throws -> PlatformDifferencesCapabilityStatus {
            switch try readInt32() {
            case 1:
                return .available
            case 2:
                return .limited
            case 3:
                return .notAvailable
            case 4:
                return .unknown
            case let value:
                throw PlatformCapabilityFFIError.unexpectedEnumCase(value)
            }
        }

        mutating func readOptionalString() throws -> String? {
            switch try readInt8() {
            case 0:
                return nil
            case 1:
                return try readString()
            case let tag:
                throw PlatformCapabilityFFIError.unexpectedOptionalTag(tag)
            }
        }

        mutating func readString() throws -> String {
            let count = try Int(readInt32())
            guard count >= 0, data.count >= offset + count else {
                throw PlatformCapabilityFFIError.bufferOverflow
            }
            defer { offset += count }
            return String(decoding: data[offset ..< offset + count], as: UTF8.self)
        }

        mutating func readBool() throws -> Bool {
            try readInt8() != 0
        }

        mutating func readInt8() throws -> Int8 {
            guard data.count >= offset + 1 else {
                throw PlatformCapabilityFFIError.bufferOverflow
            }
            defer { offset += 1 }
            return Int8(bitPattern: data[offset])
        }

        mutating func readInt32() throws -> Int32 {
            guard data.count >= offset + 4 else {
                throw PlatformCapabilityFFIError.bufferOverflow
            }
            defer { offset += 4 }
            var value: Int32 = 0
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset ..< offset + 4) }
            return value.bigEndian
        }
    }
}

private extension PlatformDifferencesPlatformId {
    var coreEnumTag: Int32 {
        switch self {
        case .macos: 1
        case .ios: 2
        case .windows: 3
        case .linux: 4
        case .unknown: 5
        }
    }
}
