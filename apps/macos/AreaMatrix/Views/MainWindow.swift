import SwiftUI

struct MainWindow: View {
    var body: some View {
        ContentUnavailableView {
            Label("AreaMatrix", systemImage: "rectangle.stack")
        } description: {
            Text("App shell")
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
