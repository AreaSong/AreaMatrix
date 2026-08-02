import SwiftUI

struct AreaMatrixFeatureCardSpec<ID: Hashable>: Identifiable {
    let id: ID
    let icon: AreaMatrixLucideIcon.IconName
    let title: String
    let description: String
    let accentColor: Color
    let entranceDelay: Double
}

struct AreaMatrixFeatureCardGroup<ID: Hashable>: View {
    let cards: [AreaMatrixFeatureCardSpec<ID>]
    let activeID: ID?
    var spacing: CGFloat = 20
    let onHoverChanged: (ID, Bool) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(cards) { card in
                AreaMatrixFeatureCard(
                    icon: card.icon,
                    title: card.title,
                    description: card.description,
                    accentColor: card.accentColor,
                    isHovered: activeID == card.id,
                    entranceDelay: card.entranceDelay,
                    anyCardHovered: isAnyCardHovered,
                    onHoverChanged: { hovering in
                        onHoverChanged(card.id, hovering)
                    }
                )
            }
        }
    }

    private var isAnyCardHovered: Bool {
        guard let activeID else { return false }
        return cards.contains { $0.id == activeID }
    }
}

struct AreaMatrixFeatureCard: View {
    let icon: AreaMatrixLucideIcon.IconName
    let title: String
    let description: String
    let accentColor: Color
    let isHovered: Bool
    let entranceDelay: Double
    let anyCardHovered: Bool
    let onHoverChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var hasEntered = false
    @State private var hoverPoint = UnitPoint.center
    @FocusState private var isFocused: Bool
    @State private var idleGlarePhase: CGFloat = -0.5

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                stableHitArea(in: proxy.size)
                cardContent
            }
            .onAppear {
                hasEntered = true
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false).delay(6.0 + entranceDelay)) {
                    idleGlarePhase = 1.5
                }
            }
        }
    }

    private func stableHitArea(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(true)
            .focused($isFocused)
            .focusEffectDisabled()
            .onChange(of: isFocused) { _, focused in
                if focused {
                    interactionFeedback.performHaptic(.alignment)
                }
                onHoverChanged(focused)
            }
            .onContinuousHover { phase in
                updateHover(phase: phase, in: size)
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            iconBox
            titleText
            descriptionText
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(cardSpotlight)
        .overlay(cardBorder)
        .overlay(cardTopAccent, alignment: .top)
        .overlay(cardGlare)
        .overlay(cardIdleGlare)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.05), radius: isHovered ? 24 : 10, y: isHovered ? 12 : 4)
        .offset(y: hasEntered ? 0 : 16)
        .opacity(hasEntered ? 1 : 0)
        .rotation3DEffect(.degrees(hasEntered ? 0 : 5), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .areaMatrixFeatureCardFocus(isHovered: isHovered, anyCardHovered: anyCardHovered)
        .animation(.easeOut(duration: 0.15), value: hoverPoint)
        .allowsHitTesting(false)
        .animation(.areaMatrixSceneFlow.delay(entranceDelay), value: hasEntered)
    }

    private var iconBox: some View {
        Color.clear
            .frame(width: 40, height: 40)
            .overlay(
                AreaMatrixLucideIcon(name: icon, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .foregroundColor(isHovered ? .white : accentColor)
            )
            .background(isHovered ? accentColor : Color.primary.opacity(0.05))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .shadow(color: isHovered ? accentColor.opacity(0.5) : .clear, radius: 16, y: 4)
            .padding(.bottom, 8)
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var descriptionText: some View {
        Text(description)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .minimumScaleFactor(0.9)
    }

    private var cardSpotlight: some View {
        RadialGradient(
            colors: [
                Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.08 : 0.05) : 0),
                .clear
            ],
            center: hoverPoint,
            startRadius: 0,
            endRadius: 180
        )
        .blendMode(colorScheme == .dark ? .screen : .normal)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cardIdleGlare: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(colorScheme == .dark ? 0.35 : 0.7), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: 250)
        .offset(x: (idleGlarePhase * 800) - 400)
        .mask(RoundedRectangle(cornerRadius: 8))
        .opacity(isHovered ? 0 : 1)
        .allowsHitTesting(false)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                LinearGradient(
                    colors: [
                        isHovered ? Color.primary.opacity(0.3) : Color.primary.opacity(0.1),
                        Color.primary.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var cardTopAccent: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(accentColor)
                .frame(width: isHovered ? proxy.size.width : 40, height: 3)
                .frame(maxWidth: .infinity)
                .shadow(color: isHovered ? accentColor.opacity(0.8) : .clear, radius: 12)
        }
        .frame(height: 3)
        .opacity(isHovered ? 1 : 0.5)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isHovered)
    }

    private var cardGlare: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: proxy.size.width * 2, height: proxy.size.height * 2)
            .rotationEffect(.degrees(-20))
            .offset(
                x: (hoverPoint.x - 0.5) * proxy.size.width * 1.5,
                y: (hoverPoint.y - 0.5) * proxy.size.height * 1.5
            )
            .opacity(isHovered ? 1 : 0)
            .blendMode(colorScheme == .dark ? .plusLighter : .screen)
        }
        .allowsHitTesting(false)
    }

    private func updateHover(phase: HoverPhase, in size: CGSize) {
        switch phase {
        case let .active(location):
            hoverPoint = UnitPoint(
                x: max(0, min(1, location.x / max(size.width, 1))),
                y: max(0, min(1, location.y / max(size.height, 1)))
            )
            if !isHovered {
                interactionFeedback.performHaptic(.levelChange)
                onHoverChanged(true)
            }
        case .ended:
            if isHovered {
                hoverPoint = .center
                onHoverChanged(false)
            }
        }
    }
}

// MARK: - Lucide Icons

struct AreaMatrixLucideIcon: View {
    enum IconName {
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

    let name: IconName
    var lineWidth: CGFloat = 2.0

    var body: some View {
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

private struct LucideFolderShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 20, y: 20))
        path.addArc(tangent1End: CGPoint(x: 22, y: 20), tangent2End: CGPoint(x: 22, y: 18), radius: 2)
        path.addLine(to: CGPoint(x: 22, y: 8))
        path.addArc(tangent1End: CGPoint(x: 22, y: 6), tangent2End: CGPoint(x: 20, y: 6), radius: 2)
        path.addLine(to: CGPoint(x: 12.1, y: 6))

        path.addLine(to: CGPoint(x: 10.41, y: 4.1))
        path.addArc(tangent1End: CGPoint(x: 9.6, y: 3.9), tangent2End: CGPoint(x: 7.93, y: 3), radius: 2)
        path.addLine(to: CGPoint(x: 4, y: 3))
        path.addArc(tangent1End: CGPoint(x: 2, y: 3), tangent2End: CGPoint(x: 2, y: 5), radius: 2)
        path.addLine(to: CGPoint(x: 2, y: 18))
        path.addArc(tangent1End: CGPoint(x: 2, y: 20), tangent2End: CGPoint(x: 4, y: 20), radius: 2)
        path.closeSubpath()
        return path
    }
}

private struct LucideShieldCheckShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 22))
        path.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 20, y: 18), control2: CGPoint(x: 20, y: 12))
        path.addLine(to: CGPoint(x: 20, y: 5))
        path.addLine(to: CGPoint(x: 12, y: 2))
        path.addLine(to: CGPoint(x: 4, y: 5))
        path.addLine(to: CGPoint(x: 4, y: 12))
        path.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 4, y: 18), control2: CGPoint(x: 12, y: 22))

        path.move(to: CGPoint(x: 9, y: 12))
        path.addLine(to: CGPoint(x: 11, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 10))
        return path
    }
}

private struct LucideFilesShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 15.5, y: 2))
        path.addLine(to: CGPoint(x: 8.6, y: 2))
        path.addQuadCurve(to: CGPoint(x: 7, y: 3.6), control: CGPoint(x: 7, y: 2))
        path.addLine(to: CGPoint(x: 7, y: 16.4))
        path.addQuadCurve(to: CGPoint(x: 8.6, y: 18), control: CGPoint(x: 7, y: 18))
        path.addLine(to: CGPoint(x: 18.4, y: 18))
        path.addQuadCurve(to: CGPoint(x: 20, y: 16.4), control: CGPoint(x: 20, y: 18))
        path.addLine(to: CGPoint(x: 20, y: 6.5))
        path.closeSubpath()

        path.move(to: CGPoint(x: 15, y: 2))
        path.addLine(to: CGPoint(x: 15, y: 7))
        path.addLine(to: CGPoint(x: 20, y: 7))

        path.move(to: CGPoint(x: 3, y: 7.6))
        path.addLine(to: CGPoint(x: 3, y: 20.4))
        path.addQuadCurve(to: CGPoint(x: 4.6, y: 22), control: CGPoint(x: 3, y: 22))
        path.addLine(to: CGPoint(x: 14.4, y: 22))
        return path
    }
}

private struct LucideArrowRightShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 5, y: 12))
        path.addLine(to: CGPoint(x: 19, y: 12))
        path.move(to: CGPoint(x: 12, y: 5))
        path.addLine(to: CGPoint(x: 19, y: 12))
        path.move(to: CGPoint(x: 12, y: 19))
        path.addLine(to: CGPoint(x: 19, y: 12))
        return path
    }
}

private struct LucideArrowLeftShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 19, y: 12))
        path.addLine(to: CGPoint(x: 5, y: 12))
        path.move(to: CGPoint(x: 12, y: 5))
        path.addLine(to: CGPoint(x: 5, y: 12))
        path.move(to: CGPoint(x: 12, y: 19))
        path.addLine(to: CGPoint(x: 5, y: 12))
        return path
    }
}

private struct LucideGlobeShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        path.move(to: CGPoint(x: 2, y: 12))
        path.addLine(to: CGPoint(x: 22, y: 12))

        let ellipse = Path { ellipsePath in
            ellipsePath.addEllipse(in: CGRect(x: 6, y: 2, width: 12, height: 20))
        }
        path.addPath(ellipse)
        return path
    }
}

private struct LucideInfoShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        path.move(to: CGPoint(x: 12, y: 16))
        path.addLine(to: CGPoint(x: 12, y: 12))
        path.move(to: CGPoint(x: 12, y: 8))
        path.addLine(to: CGPoint(x: 12.01, y: 8))
        return path
    }
}
