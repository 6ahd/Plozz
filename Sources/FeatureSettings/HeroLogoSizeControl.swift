#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct HeroLogoSizeControl: View {
    @Binding private var size: HeroLogoSize
    private let surface: HeroLogoSizing.Surface
    private let showsLibraryPreview: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        size: Binding<HeroLogoSize>, surface: HeroLogoSizing.Surface, showsLibraryPreview: Bool = false
    ) {
        _size = size
        self.surface = surface
        self.showsLibraryPreview = showsLibraryPreview
    }

    private var layout: HeroLogoSizing.Layout {
        #if os(tvOS)
        surface == .showcase ? .showcase : .television
        #else
        sizeClass == .compact ? .compact : .regular
        #endif
    }

    private var position: Binding<Int> {
        Binding(get: { size.position }, set: { size = HeroLogoSize.allSizes[$0] })
    }

    public var body: some View {
        #if os(tvOS)
        HStack(spacing: SettingsFormMetrics.groupInset) {
            if surface == .detail || showsLibraryPreview {
                Color.clear
                    .frame(width: 320)
                    .overlay {
                        HeroLogoSizePreview(size: size, surface: surface, layout: layout, cornerRadius: 0)
                            .aspectRatio(16.0 / 9.0, contentMode: .fill)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: size)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SettingsRowMetrics.formRowCornerRadius))
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsStepper(
                    options: Array(HeroLogoSize.allSizes.indices), selection: position, compact: true,
                    label: "Logo size", rangeLabels: ("Small", "Large"),
                    rangeMidpointLabel: "Default",
                    title: { $0 == HeroLogoSize.default.position ? "Default" : "\($0 + 1) of \(HeroLogoSize.allSizes.count)" }
                )
                .accessibilityIdentifier("logo-size-adjustment")
                Button("Reset") { size = .default }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(SettingsRowMetrics.helperFont)
                    .disabled(size == .default)
                    .accessibilityLabel(Text("Reset to default"))
                    .accessibilityIdentifier("logo-size-reset")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.settingsFormRowsFlushLeading, false)
        .accessibilityElement(children: .contain)
        #else
        VStack(alignment: .leading, spacing: 20) {
            HeroLogoSizePreview(size: size, surface: surface, layout: layout)
                .frame(maxWidth: 720)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: size)
            Slider(
                value: Binding(
                    get: { Double(position.wrappedValue) },
                    set: { position.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...Double(HeroLogoSize.allSizes.count - 1),
                step: 1
            ) {
                Text("Logo size")
            } minimumValueLabel: {
                Text("Small").font(.caption)
            } maximumValueLabel: {
                Text("Large").font(.caption)
            }
            .accessibilityValue(
                size == .default ? Text("Default") : Text("\(size.position + 1) of \(HeroLogoSize.allSizes.count)")
            )
            .accessibilityIdentifier("logo-size-adjustment")
            Text("Default").font(.caption).frame(maxWidth: .infinity)
            Button("Reset to default") { size = .default }
                .disabled(size == .default)
                .accessibilityIdentifier("logo-size-reset")
        }
        .accessibilityElement(children: .contain)
        #endif
    }
}
#endif
