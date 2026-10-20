#if canImport(SwiftUI)
import CoreModels
import SwiftUI

private struct ContinueWatchingPortraitDetailsKey: EnvironmentKey {
    static let defaultValue = ContinueWatchingPortraitDetails.default
}

public extension EnvironmentValues {
    var plozzContinueWatchingPortraitDetails: ContinueWatchingPortraitDetails {
        get { self[ContinueWatchingPortraitDetailsKey.self] }
        set { self[ContinueWatchingPortraitDetailsKey.self] = newValue }
    }
}

public extension ContinueWatchingPortraitDetails {
    var cardAspectRatio: CGFloat {
        self == .detailed ? ContinueWatchingCardShape.portraitAspectRatio : 2.0 / 3.0
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .detailed: "Detailed"
        case .progressOnly: "Progress only"
        }
    }
    var detail: LocalizedStringResource {
        switch self {
        case .detailed: "Playback information in a softly blurred reflection."
        case .progressOnly: "A progress bar over the poster, without playback text."
        }
    }
}
#endif
