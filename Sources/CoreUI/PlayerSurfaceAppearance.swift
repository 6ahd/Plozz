#if canImport(SwiftUI)
import SwiftUI

public extension EnvironmentValues {
    var playerUsesNativeGlass: Bool {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return !plozzReducePanelGlass && !plozzReduceTransparency
        }
        return false
    }
}

@available(iOS 26.0, tvOS 26.0, *)
public struct PlayerNativeGlassSurface<S: Shape>: View {
    private let shape: S

    public init(_ shape: S) {
        self.shape = shape
    }

    public var body: some View {
        Color.clear.glassEffect(.regular, in: shape)
    }
}
#endif
