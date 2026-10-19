#if canImport(SwiftUI)
import CoreUI
import SwiftUI

public enum PlayerTouchLayout {
    public static let edgeInset: CGFloat = 24
    public static let horizontalInset: CGFloat = 21
    public static let playDiameter: CGFloat = 92
    public static let skipDiameter: CGFloat = 64
    public static let timelineRowHeight: CGFloat = 38

    public static func usesCompactTransport(contentHeight: CGFloat) -> Bool {
        contentHeight > 0 && contentHeight < 352
    }

    public static func transportSpacing(availableWidth: CGFloat, portrait: Bool = false) -> CGFloat {
        min(portrait ? 39 : 68, max(0, (availableWidth - playDiameter - 2 * skipDiameter) / 2))
    }
}

/// Keep native edge margins without adding them to the window's safe area.
#if os(iOS)
public struct PlayerTouchChromePadding: ViewModifier {
    private let isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        content.modifier(WindowSafeAreaPadding(
            isEnabled: isEnabled, minimumInset: PlayerTouchLayout.edgeInset,
            minimumHorizontalInset: PlayerTouchLayout.horizontalInset
        ))
    }
}
#endif

public struct PlayerGlassControlGroup<Content: View>: View {
    private let content: Content
    @Environment(\.playerUsesNativeGlass) private var nativeGlass

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Group {
            if nativeGlass, #available(iOS 26.0, tvOS 26.0, *) {
                #if os(iOS)
                controls.glassEffect(.clear, in: Capsule())
                #else
                controls.glassEffect(.regular, in: Capsule())
                #endif
            } else {
                controls
                    .plozzFrostedBackground(Capsule())
                    .plozzFrostedBorder(Capsule())
            }
        }
        .environment(\.playerControlsGrouped, true)
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        HStack(spacing: 12) { content }
    }
}

private struct PlayerControlsGroupedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var playerControlsGrouped: Bool {
        get { self[PlayerControlsGroupedKey.self] }
        set { self[PlayerControlsGroupedKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func playerTouchTab(selected: Bool) -> some View {
        modifier(PlayerTouchTabModifier(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PlayerTouchTabModifier: ViewModifier {
    let selected: Bool
    @Environment(\.playerUsesNativeGlass) private var nativeGlass

    func body(content: Content) -> some View {
        if nativeGlass, #available(iOS 26.0, tvOS 26.0, *) {
            content
                .buttonStyle(PlayerNativeTouchTabStyle())
                .controlSize(.regular)
                .buttonSizing(.flexible)
                .frame(minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            content.buttonStyle(PlayerTabButtonStyle(focused: false, selected: selected))
        }
    }
}

@available(iOS 26.0, tvOS 26.0, *)
private struct PlayerNativeTouchTabStyle: PrimitiveButtonStyle {
    @Environment(\.playerControlForeground) private var foreground

    func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            button(configuration).buttonStyle(.glass(.clear))
        } else {
            button(configuration).buttonStyle(PlayerClearTouchTabStyle())
        }
        #else
        button(configuration).buttonStyle(.glass)
        #endif
    }

    private func button(_ configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 2)
                .frame(minHeight: 28)
        }
    }
}

#if os(iOS)
@available(iOS 26.0, *)
private struct PlayerClearTouchTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.clear.interactive(), in: Capsule())
    }
}
#endif
#endif
