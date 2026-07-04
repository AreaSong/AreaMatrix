@testable import AreaMatrix

extension RecordingCoreErrorMapper {
    static func importSingleFile() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importSingleFileError(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }

    static func importCopy() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importCopyFixture(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }

    static func importMove() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importMoveFixture(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }

    static func importIndex() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importIndexFixture(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }
}
