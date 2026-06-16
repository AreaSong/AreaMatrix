import AppKit
import SwiftUI

struct AreaMatrixFeatureCardSpec<ID: Hashable>: Identifiable {
    let id: ID
    let icon: String
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
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let isHovered: Bool
    let entranceDelay: Double
    let anyCardHovered: Bool
    let onHoverChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
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
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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
        .padding(.vertical, 24)
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
        .animation(.areaMatrixStageFlow.delay(entranceDelay), value: hasEntered)
    }

    private var iconBox: some View {
        Color.clear
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .symbolEffect(.bounce, value: isHovered)
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
    }

    private var descriptionText: some View {
        Text(description)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .lineLimit(1)
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
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
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
