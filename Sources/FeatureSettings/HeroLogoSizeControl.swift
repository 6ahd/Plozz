#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct HeroLogoSizeControl: View {
    @Binding private var size: HeroLogoSize
    private let surface: HeroLogoSizing.Surface
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: Binding<HeroLogoSize>, surface: HeroLogoSizing.Surface) {
        _size = size
        self.surface = surface
    }

    private var layout: HeroLogoSizing.Layout {
        #if os(tvOS)
        surface == .showcase ? .showcase : .television
        #else
        sizeClass == .compact ? .compact : .regular
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroLogoSizePreview(size: size, surface: surface, layout: layout)
                .frame(maxWidth: 720)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: size)
            #if os(tvOS)
            SettingsStepper(
                options: HeroLogoSize.allSizes, selection: $size,
                label: "Logo size", rangeLabels: ("Small", "Large"),
                title: { "\($0.rawValue + 1) of \(HeroLogoSize.allSizes.count)" }
            )
            .accessibilityIdentifier("logo-size-adjustment")
            #else
            Slider(
                value: Binding(
                    get: { Double(size.rawValue) },
                    set: { size = HeroLogoSize(rawValue: Int($0.rounded())) }
                ),
                in: Double(HeroLogoSize.steps.lowerBound)...Double(HeroLogoSize.steps.upperBound),
                step: 1
            ) {
                Text("Logo size")
            } minimumValueLabel: {
                Text("Small").font(.caption)
            } maximumValueLabel: {
                Text("Large").font(.caption)
            }
            .accessibilityValue(Text("\(size.rawValue + 1) of \(HeroLogoSize.allSizes.count)"))
            .accessibilityIdentifier("logo-size-adjustment")
            #endif
            Button("Reset to default") { size = .default }
                .disabled(size == .default)
                .accessibilityIdentifier("logo-size-reset")
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
