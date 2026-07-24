import Carea_matrixFFI
import Foundation

enum MobileRepositoryFFIWriter {
    static func lowerString(_ value: String) throws -> RustBuffer {
        try value.utf8CString.withUnsafeBufferPointer { int8Pointer in
            try int8Pointer.withMemoryRebound(to: UInt8.self) { pointer in
                let bytes = UnsafeBufferPointer(rebasing: pointer.prefix(upTo: pointer.count - 1))
                return try lowerBytes(bytes)
            }
        }
    }

    static func lowerRepoInitOptions(
        mode: MobileRepositoryInitMode,
        createDefaultCategories: Bool,
        overviewOutput: MobileRepositoryOverviewOutput
    ) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt32(enumValue(for: mode), into: &bytes)
        writeBool(createDefaultCategories, into: &bytes)
        writeInt32(overviewOutput.rawValue, into: &bytes)
        writeInt32(1, into: &bytes)
        writeInt32(preferredContentLocale().rawValue, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    static func preferredContentLocale() -> MobileRepositoryContentLocale {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .zhHans : .en
    }

    static func contentLocale(for policy: String) throws -> MobileRepositoryContentLocale {
        switch policy.lowercased() {
        case "follow-interface", "system":
            preferredContentLocale()
        case "zh-hans":
            .zhHans
        case "en":
            .en
        default:
            throw MobileRepositoryCoreFFIError.unsupportedRepositoryLocale(policy)
        }
    }

    static func lowerRepoConfigPatch(_ config: MobileRepositoryConfig) throws -> RustBuffer {
        var bytes: [UInt8] = []
        writeInt64(config.revision, into: &bytes)
        writeOptionalString(config.repoPath, into: &bytes)
        writeOptionalStorageMode(config.defaultMode, into: &bytes)
        writeOptionalOverviewOutput(config.overviewOutput, into: &bytes)
        writeOptionalBool(config.aiEnabled, into: &bytes)
        try writeOptionalRepositoryLocale(config.locale, into: &bytes)
        writeOptionalBool(config.iCloudWarn, into: &bytes)
        writeOptionalBool(config.enableExtensionRules, into: &bytes)
        writeOptionalBool(config.enableKeywordRules, into: &bytes)
        writeOptionalBool(config.fallbackToInbox, into: &bytes)
        writeOptionalBool(config.allowReplaceDuringImport, into: &bytes)
        return try bytes.withUnsafeBufferPointer { try lowerBytes($0) }
    }

    private static func writeOptionalStorageMode(_ value: String, into bytes: inout [UInt8]) {
        writeBool(true, into: &bytes)
        writeStorageMode(value, into: &bytes)
    }

    private static func writeOptionalOverviewOutput(_ value: String, into bytes: inout [UInt8]) {
        writeBool(true, into: &bytes)
        writeOverviewOutput(value, into: &bytes)
    }

    private static func writeOptionalBool(_ value: Bool, into bytes: inout [UInt8]) {
        writeBool(true, into: &bytes)
        writeBool(value, into: &bytes)
    }

    private static func writeOptionalRepositoryLocale(_ value: String, into bytes: inout [UInt8]) throws {
        writeBool(true, into: &bytes)
        switch value.lowercased() {
        case "follow-interface", "system":
            writeInt32(1, into: &bytes)
        case "zh-hans":
            writeInt32(2, into: &bytes)
        case "en":
            writeInt32(3, into: &bytes)
        default:
            throw MobileRepositoryCoreFFIError.unsupportedRepositoryLocale(value)
        }
    }

    private static func writeOptionalString(_ value: String?, into bytes: inout [UInt8]) {
        guard let value else {
            bytes.append(0)
            return
        }
        bytes.append(1)
        let data = Array(value.utf8)
        writeInt32(Int32(data.count), into: &bytes)
        bytes.append(contentsOf: data)
    }

    private static func enumValue(for mode: MobileRepositoryInitMode) -> Int32 {
        switch mode {
        case .createEmpty:
            1
        case .adoptExisting:
            2
        }
    }

    private static func writeStorageMode(_ value: String, into bytes: inout [UInt8]) {
        switch value {
        case "Moved":
            writeInt32(1, into: &bytes)
        case "Copied":
            writeInt32(2, into: &bytes)
        case "Indexed":
            writeInt32(3, into: &bytes)
        default:
            writeInt32(2, into: &bytes)
        }
    }

    private static func writeOverviewOutput(_ value: String, into bytes: inout [UInt8]) {
        writeInt32(value == "RootAreaMatrixFile" ? 2 : 1, into: &bytes)
    }

    private static func lowerBytes(_ bytes: UnsafeBufferPointer<UInt8>) throws -> RustBuffer {
        var status = RustCallStatus()
        let buffer = ffi_area_matrix_core_rustbuffer_from_bytes(
            ForeignBytes(len: Int32(bytes.count), data: bytes.baseAddress),
            &status
        )
        guard status.code == 0 else {
            throw MobileRepositoryCoreFFIError.unexpectedStatus(status.code)
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

    private static func writeInt64(_ value: Int64, into bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}
