import Darwin

struct DiagnosticPackagePublishOperations {
    let synchronize: @Sendable (Int32) -> Int32
    let renameExclusive: @Sendable (Int32, String, Int32, String, UInt32) -> Int32
    let beforeStageCopy: @Sendable (Int32) -> Void
    let beforePublish: @Sendable (Int32) -> Void
    let beforeCleanup: @Sendable (Int32) -> Void

    init(
        synchronize: @escaping @Sendable (Int32) -> Int32,
        renameExclusive: @escaping @Sendable (Int32, String, Int32, String, UInt32) -> Int32,
        beforeStageCopy: @escaping @Sendable (Int32) -> Void = { _ in },
        beforePublish: @escaping @Sendable (Int32) -> Void = { _ in },
        beforeCleanup: @escaping @Sendable (Int32) -> Void = { _ in }
    ) {
        self.synchronize = synchronize
        self.renameExclusive = renameExclusive
        self.beforeStageCopy = beforeStageCopy
        self.beforePublish = beforePublish
        self.beforeCleanup = beforeCleanup
    }

    static let live = Self(
        synchronize: { Darwin.fsync($0) },
        renameExclusive: { sourceDirectory, source, targetDirectory, target, flags in
            renameatx_np(sourceDirectory, source, targetDirectory, target, flags)
        }
    )
}
