#if canImport(SwiftUI)
import SwiftUI

public extension EnvironmentValues {
    var playerUsesNativeGlass: Bool {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return !plozzReducePanelGlass && !plozzReduceTransparency
        }
        return false
    }

    var playerSurfaceColorScheme: ColorScheme {
        playerUsesNativeGlass ? .dark : colorScheme
    }
}

public extension View {
    /// Scope to a playback surface and its content, never the player or a sheet host.
    func playerSurfaceAppearance() -> some View {
        modifier(PlayerSurfaceAppearance())
    }
}

@available(iOS 26.0, tvOS 26.0, *)
public struct PlayerNativeGlassSurface<S: Shape>: View {
    private let shape: S
    private let highlighted: Bool

    public init(_ shape: S, highlighted: Bool = false) {
        self.shape = shape
        self.highlighted = highlighted
    }

    public var body: some View {
        Color.clear.glassEffect(PlayerNativeGlass.material(highlighted: highlighted), in: shape)
            .environment(\.colorScheme, .dark)
    }
}

@available(iOS 26.0, tvOS 26.0, *)
enum PlayerNativeGlass {
    static func material(highlighted: Bool = false) -> Glass {
        // Regular glass recolors itself over bright video even with a dark scheme.
        .clear.tint(Color(white: highlighted ? 0.12 : 0).opacity(highlighted ? 0.70 : 0.60))
    }
}

private struct PlayerSurfaceAppearance: ViewModifier {
    @Environment(\.playerSurfaceColorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, colorScheme)
            .environment(\.themePalette, colorScheme == .light ? .light : (palette.isLight ? .dark : palette))
    }
}
#endif
