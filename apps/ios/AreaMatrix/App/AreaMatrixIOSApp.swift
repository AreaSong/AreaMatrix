import SwiftUI

public struct ConnectRepositoryEntryView: View {
    @StateObject private var model = ConnectRepositoryModel(bridge: LiveMobileRepositoryCoreBridge())

    public init() {}

    public var body: some View {
        ConnectRepositoryView(model: model)
    }
}
