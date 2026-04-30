import SwiftUI

struct MainWindow: View {
    @State private var model = AppShellModel()

    var body: some View {
        ContentUnavailableView {
            Label("AreaMatrix", systemImage: "tray")
        } description: {
            Text(model.statusText)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
