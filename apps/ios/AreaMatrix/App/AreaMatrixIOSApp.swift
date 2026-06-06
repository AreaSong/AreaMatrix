import SwiftUI

public struct ConnectRepositoryEntryView: View {
    @StateObject private var model = ConnectRepositoryModel(bridge: LiveMobileRepositoryCoreBridge())

    public init() {}

    public var body: some View {
        Group {
            if let connection = model.shareImportTakeoverConnection {
                NavigationStack {
                    MobileLibraryView(connection: connection, bridge: LiveMobileRepositoryCoreBridge())
                }
            } else {
                ConnectRepositoryView(model: model)
            }
        }
        .onOpenURL { url in
            Task { await model.handleOpenURL(url) }
        }
    }
}
