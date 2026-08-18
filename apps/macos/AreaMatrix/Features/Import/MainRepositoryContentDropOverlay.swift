import SwiftUI

struct MainRepositoryDropOverlay: View {
    let presentation: ImportDropPreviewPresentation?

    var body: some View {
        Group {
            if let presentation {
                DropZoneOverlay(presentation: presentation)
                    .padding(24)
            }
        }
    }
}
