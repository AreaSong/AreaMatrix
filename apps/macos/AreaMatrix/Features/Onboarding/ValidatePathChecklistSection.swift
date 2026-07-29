import SwiftUI

struct ValidatePathSatelliteRadar: View {
    let displayedPath: String
    let validation: RepoPathValidationSnapshot?
    let isValidating: Bool
    let errorMessage: LocalizedMessage?

    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 64) {
            // ================= 左翼 4 颗伴星 =================
            VStack(alignment: .trailing, spacing: 32) {
                ForEach(0 ..< min(4, rows.count), id: \.self) { index in
                    ValidatePathSatelliteNode(row: rows[index], alignment: .trailing, index: index)
                }
            }
            .frame(width: 220, alignment: .trailing)

            // ================= 巨型中心雷达 =================
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
                    .foregroundStyle(AreaMatrixTheme.Colors.teal.opacity(0.2))
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(rotation * 0.5))

                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(AreaMatrixTheme.Colors.teal.opacity(0.15))
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-rotation * 0.8))

                Circle()
                    .strokeBorder(AreaMatrixTheme.Colors.teal.opacity(0.1), lineWidth: 1)
                    .frame(width: 160, height: 160)

                if isValidating {
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    AreaMatrixTheme.Colors.teal.opacity(0.0),
                                    AreaMatrixTheme.Colors.teal.opacity(0.3)
                                ]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            )
                        )
                        .frame(width: 280, height: 280)
                        .rotationEffect(.degrees(rotation * 1.5))
                }

                Circle()
                    .fill(AreaMatrixTheme.Colors.teal.opacity(0.06))
                    .frame(width: 120 * pulse, height: 120 * pulse)

                Group {
                    if isValidating {
                        AreaMatrixLucideIcon(name: .refreshCcw, lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(AreaMatrixTheme.Colors.teal)
                            .rotationEffect(.degrees(rotation * 2))
                    } else if validation?.isInitialized == true {
                        AreaMatrixLucideIcon(name: .checkCircle, lineWidth: 2)
                            .frame(width: 64, height: 64)
                            .foregroundStyle(AreaMatrixTheme.Colors.teal)
                    } else if errorMessage != nil {
                        AreaMatrixLucideIcon(name: .alertTriangle, lineWidth: 2)
                            .frame(width: 64, height: 64)
                            .foregroundStyle(AreaMatrixTheme.Colors.coral)
                    } else {
                        AreaMatrixLucideIcon(name: .hardDrive, lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(AreaMatrixTheme.Colors.teal.opacity(0.5))
                    }
                }
                .scaleEffect(pulse)
            }
            .frame(width: 280, height: 280)
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = 1.05
                }
            }

            // ================= 右翼 4 颗伴星 =================
            VStack(alignment: .leading, spacing: 32) {
                if rows.count > 4 {
                    ForEach(4 ..< rows.count, id: \.self) { index in
                        ValidatePathSatelliteNode(row: rows[index], alignment: .leading, index: index)
                    }
                } else {
                    Spacer().frame(height: 1)
                }
            }
            .frame(width: 220, alignment: .leading)
        }
    }

    private var rows: [ValidatePathCheckRow] {
        guard let validation else {
            return [
                .init(L10n.string("onboarding.validate.check.directory"), displayedPath, .checking),
                .init(L10n.string("onboarding.validate.check.readable"), waitingForCore, .checking),
                .init(L10n.string("onboarding.validate.check.writable"), waitingForCore, .checking),
                .init(
                    L10n.string("onboarding.validate.check.capacity"),
                    L10n.string("onboarding.validate.check.waitingCapacity"),
                    .checking
                ),
                .init(L10n.string("onboarding.validate.check.icloud"), waitingForCore, .checking),
                .init(
                    L10n.string("onboarding.validate.check.externalVolume"),
                    L10n.string("onboarding.validate.check.waitingVolume"),
                    .checking
                ),
                .init(L10n.string("onboarding.validate.check.existingRepo"), waitingForCore, .checking),
                .init(L10n.string("onboarding.validate.check.nonEmpty"), waitingForCore, .checking)
            ]
        }

        let isUsableDirectory = validation.exists && validation.isDirectory
        let hasNonEmptyDirectory = validation.issues.contains(.nonEmptyDirectory)

        return [
            .init(
                L10n.string("onboarding.validate.check.directory"),
                isUsableDirectory ? L10n.string("onboarding.validate.check.candidateDirectory") : L10n
                    .string("onboarding.validate.check.chooseExistingFolder"),
                isUsableDirectory ? .passed : .failed
            ),
            .init(
                L10n.string("onboarding.validate.check.readable"),
                statusDetail(validation.isReadable),
                validation.isReadable ? .passed : .failed
            ),
            .init(
                L10n.string("onboarding.validate.check.writable"),
                statusDetail(validation.isWritable),
                validation.isWritable ? .passed : .failed
            ),
            .init(
                L10n.string("onboarding.validate.check.capacity"),
                capacityDetail(for: validation),
                capacityStatus(for: validation)
            ),
            .init(
                L10n.string("onboarding.validate.check.icloud"),
                validation.isICloudPath ? warningDetail : passedDetail,
                validation.isICloudPath ? .warning : .passed
            ),
            .init(
                L10n.string("onboarding.validate.check.externalVolume"),
                externalVolumeDetail(for: validation),
                externalVolumeStatus(for: validation)
            ),
            .init(
                L10n.string("onboarding.validate.check.existingRepo"),
                validation.isInitialized ? warningDetail : passedDetail,
                validation.isInitialized ? .warning : .passed
            ),
            .init(
                L10n.string("onboarding.validate.check.nonEmpty"),
                hasNonEmptyDirectory ? warningDetail : passedDetail,
                hasNonEmptyDirectory ? .warning : .passed
            )
        ]
    }

    private var waitingForCore: String {
        L10n.string("onboarding.validate.check.waitingCore")
    }

    private var passedDetail: String {
        L10n.string("onboarding.validate.check.passed")
    }

    private var warningDetail: String {
        L10n.string("onboarding.validate.check.warning")
    }

    private func statusDetail(_ passed: Bool) -> String {
        passed ? passedDetail : L10n.string("onboarding.validate.check.failed")
    }

    private func capacityDetail(for validation: RepoPathValidationSnapshot) -> String {
        guard let bytes = validation.availableCapacityBytes else {
            return L10n.string("onboarding.validate.check.missingResult")
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func capacityStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        if validation.hasInsufficientAvailableCapacity { return .failed }
        return validation.availableCapacityBytes == nil ? .failed : .passed
    }

    private func externalVolumeDetail(for validation: RepoPathValidationSnapshot) -> String {
        switch validation.isExternalVolume {
        case .some(true): warningDetail
        case .some(false): passedDetail
        case nil: L10n.string("onboarding.validate.check.missingResult")
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

private struct ValidatePathSatelliteNode: View {
    let row: ValidatePathCheckRow
    let alignment: HorizontalAlignment
    let index: Int

    @State private var isVisible = false
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            if alignment == .leading {
                // 圆点在左侧，文字在右（雷达的右翼）
                Circle()
                    .fill(row.status.tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: row.status.tint.opacity(0.5), radius: 4)

                Text(row.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(1)
            } else {
                // 文字在左侧，圆点在右（雷达的左翼）
                Text(row.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(1)

                Circle()
                    .fill(row.status.tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: row.status.tint.opacity(0.5), radius: 4)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : (alignment == .leading ? -10 : 10), y: floatOffset)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(Double(index) * 0.1)) {
                isVisible = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(Double(index) * 0.15)) {
                floatOffset = (index % 2 == 0) ? -3 : 3
            }
        }
    }
}
