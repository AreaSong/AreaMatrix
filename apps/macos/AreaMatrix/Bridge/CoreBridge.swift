import Foundation

struct CoreBridge {
    enum BridgeState: Equatable {
        case placeholder
    }

    let state: BridgeState = .placeholder

    func coreAvailability() -> String {
        "placeholder"
    }
}
