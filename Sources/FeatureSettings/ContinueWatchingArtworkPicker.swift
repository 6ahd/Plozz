#if canImport(SwiftUI)
import SwiftUI
import CoreUI

/// Equal-weight native choices keep every presentation visible without a separate layout control.
struct ContinueWatchingArtworkPicker: View {
    @Binding var style: ContinueWatchingArtworkStyle
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesRows: Bool {
        #if os(tvOS)
        false
        #else
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        #endif
    }

    var body: some View {
        let layout = usesRows
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            ForEach(ContinueWatchingArtworkStyle.allCases, id: \.self) { option in
                Button { style = option } label: {
                    optionLabel(option)
                        .padding(12)
                }
                .plozzActionButton(role: .secondary)
                .buttonBorderShape(.roundedRectangle(radius: PlozzTheme.Metrics.Radius.panel))
                .accessibilityLabel(Text(option.displayName))
                .accessibilityHint(Text(option.detail))
                .accessibilityAddTraits(style == option ? .isSelected : [])
                .accessibilityIdentifier("continue-watching-style-\(option.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func optionLabel(_ option: ContinueWatchingArtworkStyle) -> some View {
        if usesRows {
            HStack(spacing: 16) {
                swatch(option).frame(width: 96, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.displayName).font(.headline)
                    Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                selectionMark(option)
            }
            .multilineTextAlignment(.leading)
        } else {
            VStack(spacing: 12) {
                swatch(option).frame(height: 200)
                HStack(spacing: 8) {
                    ZStack {
                        ForEach(ContinueWatchingArtworkStyle.allCases, id: \.self) { candidate in
                            Text(candidate.displayName).hidden().accessibilityHidden(true)
                        }
                        Text(option.displayName)
                    }
                    .font(SettingsRowMetrics.optionFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    selectionMark(option)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private func swatch(_ option: ContinueWatchingArtworkStyle) -> some View {
        ContinueWatchingArtworkSwatch(
            style: option, cornerRadius: PlozzTheme.Metrics.Radius.content
        )
        .accessibilityHidden(true)
    }

    private func selectionMark(_ option: ContinueWatchingArtworkStyle) -> some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .opacity(style == option ? 1 : 0)
            .accessibilityHidden(true)
    }
}
#endif
