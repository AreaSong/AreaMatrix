import SwiftUI

/// Shared route transition used by the app shell and feature-owned scenes.
public extension AnyTransition {
    static var areaMatrixScene: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: AreaMatrixSceneTransitionModifier(opacity: 0, yOffset: 20, scale: 0.96),
                identity: AreaMatrixSceneTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            ),
            removal: .modifier(
                active: AreaMatrixSceneTransitionModifier(opacity: 0, yOffset: -16, scale: 0.98),
                identity: AreaMatrixSceneTransitionModifier(opacity: 1, yOffset: 0, scale: 1)
            )
        )
    }
}

private struct AreaMatrixSceneTransitionModifier: ViewModifier {
    let opacity: Double
    let yOffset: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: yOffset)
    }
}

/// Visibility state shared by the scene switcher and its reusable dioramas.
public enum AreaMatrixSceneVisibility: Equatable, Sendable {
    case enter(isVisible: Bool)
    case exit(isVisible: Bool)

    public var isVisible: Bool {
        switch self {
        case let .enter(isVisible), let .exit(isVisible):
            isVisible
        }
    }
}

private struct AreaMatrixSceneVisibilityKey: EnvironmentKey {
    static let defaultValue = AreaMatrixSceneVisibility.enter(isVisible: true)
}

private struct AreaMatrixSceneParallaxKey: EnvironmentKey {
    static let defaultValue = AreaMatrixParallax.zero
}

public extension EnvironmentValues {
    /// Scene visibility supplied by a feature-owned scene switcher.
    var areaMatrixSceneVisibility: AreaMatrixSceneVisibility {
        get { self[AreaMatrixSceneVisibilityKey.self] }
        set { self[AreaMatrixSceneVisibilityKey.self] = newValue }
    }

    /// Pointer-derived parallax supplied by the active scene host.
    var areaMatrixSceneParallax: AreaMatrixParallax {
        get { self[AreaMatrixSceneParallaxKey.self] }
        set { self[AreaMatrixSceneParallaxKey.self] = newValue }
    }
}

public extension AreaMatrixParallax {
    init(pointerLocation location: CGPoint, in size: CGSize) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        self.init(
            horizontal: ((location.x / width) - 0.5) * 2,
            vertical: ((location.y / height) - 0.5) * 2
        )
    }

    static func fromHoverPhase(_ phase: HoverPhase, in size: CGSize) -> AreaMatrixParallax {
        switch phase {
        case let .active(location):
            AreaMatrixParallax(pointerLocation: location, in: size)
        case .ended:
            .zero
        }
    }
}

/// Reusable visual transform for scene content entering, leaving, and tracking the pointer.
public struct AreaMatrixSceneVisualMotionModifier: ViewModifier {
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility
    @Environment(\.areaMatrixSceneParallax) private var parallax
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public func body(content: Content) -> some View {
        content
            .opacity(sceneVisibility.isVisible ? 1 : 0)
            .offset(y: reduceMotion || sceneVisibility.isVisible ? 0 : verticalOffset)
            .scaleEffect(reduceMotion || sceneVisibility.isVisible ? 1 : scale)
            .blur(radius: reduceTransparency || sceneVisibility.isVisible ? 0 : 16)
            .rotationEffect(.degrees(reduceMotion || sceneVisibility.isVisible ? 0 : rotationAngle))
            .rotation3DEffect(
                .degrees(reduceMotion || sceneVisibility.isVisible ? 0 : scene3DRotation),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.85
            )
            .rotation3DEffect(
                .degrees(effectiveParallax.vertical * -12),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.75
            )
            .rotation3DEffect(
                .degrees(effectiveParallax.horizontal * 12),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.75
            )
            .animation(reduceMotion ? nil : .areaMatrixSceneEnterExit, value: sceneVisibility)
            .animation(reduceMotion ? nil : .areaMatrixSceneParallax, value: effectiveParallax)
    }

    private var effectiveParallax: AreaMatrixParallax {
        reduceMotion ? .zero : parallax
    }

    private var verticalOffset: CGFloat {
        switch sceneVisibility {
        case .enter: 16
        case .exit: -12
        }
    }

    private var scale: CGFloat {
        switch sceneVisibility {
        case .enter: 0.85
        case .exit: 1.15
        }
    }

    private var rotationAngle: Double {
        switch sceneVisibility {
        case .enter: 1.5
        case .exit: -1.5
        }
    }

    private var scene3DRotation: Double {
        switch sceneVisibility {
        case .enter: -10
        case .exit: 10
        }
    }
}

/// Reusable text entrance transform for scene copy.
public struct AreaMatrixSceneTextMotionModifier: ViewModifier {
    let delay: Double
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(delay: Double) {
        self.delay = delay
    }

    public func body(content: Content) -> some View {
        content
            .opacity(sceneVisibility.isVisible ? 1 : 0)
            .offset(y: reduceMotion || sceneVisibility.isVisible ? 0 : offsetValue)
            .blur(radius: reduceTransparency || sceneVisibility.isVisible ? 0 : 4)
            .animation(reduceMotion ? nil : animation, value: sceneVisibility)
    }

    private var offsetValue: CGFloat {
        switch sceneVisibility {
        case .enter: 12
        case .exit: -12
        }
    }

    private var animation: Animation {
        switch sceneVisibility {
        case .enter:
            .areaMatrixSceneEnterExit.delay(delay)
        case .exit:
            .timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
        }
    }
}

public extension View {
    func areaMatrixSceneVisualMotion() -> some View {
        modifier(AreaMatrixSceneVisualMotionModifier())
    }

    func areaMatrixSceneTextMotion(delay: Double) -> some View {
        modifier(AreaMatrixSceneTextMotionModifier(delay: delay))
    }
}
