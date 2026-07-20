import SwiftUI

struct ValidatePathChecklist: View {
    let displayedPath: String
    let validation: RepoPathValidationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.title) { row in
                    ValidatePathCheckRowView(row: row)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
        }
    }

    private var rows: [ValidatePathCheckRow] {
        guard let validation else {
            return [
                .init("路径存在且是文件夹", displayedPath, .checking),
                .init("可读权限", "等待 Core 校验", .checking),
                .init("可写权限", "等待 Core 校验", .checking),
                .init("可用空间", "等待容量检查", .checking),
                .init("iCloud 路径", "等待 Core 校验", .checking),
                .init("是否外置卷", "等待卷信息", .checking),
                .init("已有 AreaMatrix repo", "等待 Core 校验", .checking),
                .init("非空目录", "等待 Core 校验", .checking)
            ]
        }

        let isUsableDirectory = validation.exists && validation.isDirectory
        let hasNonEmptyDirectory = validation.issues.contains(.nonEmptyDirectory)

        return [
            .init(
                "路径存在且是文件夹",
                isUsableDirectory ? "可作为候选目录" : "请选择已存在的文件夹",
                isUsableDirectory ? .passed : .failed
            ),
            .init("可读权限", validation.isReadable ? "Passed" : "Failed", validation.isReadable ? .passed : .failed),
            .init("可写权限", validation.isWritable ? "Passed" : "Failed", validation.isWritable ? .passed : .failed),
            .init("可用空间", capacityDetail(for: validation), capacityStatus(for: validation)),
            .init(
                "iCloud 路径",
                validation.isICloudPath ? "Warning" : "Passed",
                validation.isICloudPath ? .warning : .passed
            ),
            .init("是否外置卷", externalVolumeDetail(for: validation), externalVolumeStatus(for: validation)),
            .init(
                "已有 AreaMatrix repo",
                validation.isInitialized ? "Warning" : "Passed",
                validation.isInitialized ? .warning : .passed
            ),
            .init("非空目录", hasNonEmptyDirectory ? "Warning" : "Passed", hasNonEmptyDirectory ? .warning : .passed)
        ]
    }

    private func capacityDetail(for validation: RepoPathValidationSnapshot) -> String {
        guard let bytes = validation.availableCapacityBytes else {
            return "检查结果缺失"
        }

        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func capacityStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        if validation.hasInsufficientAvailableCapacity {
            return .failed
        }

        return validation.availableCapacityBytes == nil ? .failed : .passed
    }

    private func externalVolumeDetail(for validation: RepoPathValidationSnapshot) -> String {
        switch validation.isExternalVolume {
        case .some(true): "Warning"
        case .some(false): "Passed"
        case nil: "检查结果缺失"
        }
    }

    private func externalVolumeStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        switch validation.isExternalVolume {
        case .some(true): .warning
        case .some(false): .passed
        case nil: .failed
        }
    }
}

private struct ValidatePathCheckRow: Equatable {
    let title: String
    let detail: String
    let status: ValidatePathCheckStatus

    init(_ title: String, _ detail: String, _ status: ValidatePathCheckStatus) {
        self.title = title
        self.detail = detail
        self.status = status
    }
}

private struct ValidatePathCheckRowView: View {
    let row: ValidatePathCheckRow

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                Text("\(row.status.text): \(row.detail)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: row.status.systemImage)
                .foregroundStyle(row.status.tint)
        }
    }
}
