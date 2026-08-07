import SwiftUI

/// Crossfades between light and dark asset variants without owning scene state.
public struct AreaMatrixCrossfadeAssetImage: View {
    public let darkName: String
    public let lightName: String
    public let width: CGFloat?
    public let height: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    public init(darkName: String, lightName: String, width: CGFloat?, height: CGFloat?) {
        self.darkName = darkName
        self.lightName = lightName
        self.width = width
        self.height = height
    }

    public var body: some View {
        ZStack {
            assetImage(lightName)
                .opacity(colorScheme == .dark ? 0 : 1)
            assetImage(darkName)
                .opacity(colorScheme == .dark ? 1 : 0)
        }
        .animation(.easeInOut(duration: AreaMatrixMotionTokens.Duration.sceneEnterExit), value: colorScheme)
    }

    private func assetImage(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }
}
