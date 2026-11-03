import BreezeCore
import Foundation

extension FanPreset {
    var title: String {
        switch self {
        case .standard: String(localized: "Automatic")
        case .performance: String(localized: "Performance")
        case .performancePlus: String(localized: "Performance+")
        }
    }

    var symbol: String {
        switch self {
        case .standard: "leaf"
        case .performance: "wind"
        case .performancePlus: "bolt.fill"
        }
    }
}
