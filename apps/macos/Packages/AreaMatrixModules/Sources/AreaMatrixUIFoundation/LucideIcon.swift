import SwiftUI

/// Lightweight, platform-neutral Lucide-style line icon renderer.
public struct AreaMatrixLucideIcon: View {
    public enum IconName {
        case folder
        case shieldCheck
        case files
        case arrowRight
        case arrowLeft
        case globe
        case info
        case checkCircle
        case xCircle
        case alertTriangle
        case moreHorizontal
        case hardDrive
        case folderCog
        case cloud
        case refreshCcw
        case clock
        case filePlus2
        case folderOpen
    }

    public let name: IconName
    public var lineWidth: CGFloat

    public init(name: IconName, lineWidth: CGFloat = 2) {
        self.name = name
        self.lineWidth = lineWidth
    }

    public var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / 24.0

            renderedShape
                .scaleEffect(scale, anchor: .topLeading)
                .offset(
                    x: (geometry.size.width - 24 * scale) / 2,
                    y: (geometry.size.height - 24 * scale) / 2
                )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var renderedShape: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        switch name {
        case .folder:
            LucideFolderShape().stroke(style: style)
        case .shieldCheck:
            LucideShieldCheckShape().stroke(style: style)
        case .files:
            LucideFilesShape().stroke(style: style)
        case .arrowRight:
            LucideArrowRightShape().stroke(style: style)
        case .arrowLeft:
            LucideArrowLeftShape().stroke(style: style)
        case .globe:
            LucideGlobeShape().stroke(style: style)
        case .info:
            LucideInfoShape().stroke(style: style)
        case .checkCircle:
            LucideCheckCircleShape().stroke(style: style)
        case .xCircle:
            LucideXCircleShape().stroke(style: style)
        case .alertTriangle:
            LucideAlertTriangleShape().stroke(style: style)
        case .moreHorizontal:
            LucideMoreHorizontalShape().stroke(style: style)
        case .hardDrive:
            LucideHardDriveShape().stroke(style: style)
        case .folderCog:
            LucideFolderCogShape().stroke(style: style)
        case .cloud:
            LucideCloudShape().stroke(style: style)
        case .refreshCcw:
            LucideRefreshCcw().stroke(style: style)
        case .clock:
            LucideClock().stroke(style: style)
        case .filePlus2:
            LucideFilePlus2().stroke(style: style)
        case .folderOpen:
            LucideFolderOpen().stroke(style: style)
        }
    }
}
