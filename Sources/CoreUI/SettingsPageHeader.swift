#if canImport(SwiftUI)
import SwiftUI

/// Place this heading inside the page's scrollable content, never above its viewport.
/// Add a subtitle only when the title cannot communicate the scope of the page.
public struct SettingsPageHeader: View {
    private let title: Text
    private let subtitle: Text?

    public init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle.map(Text.init)
    }

    public init(verbatim title: String, subtitle: LocalizedStringResource? = nil) { // l10n:content
        self.title = Text(verbatim: title)
        self.subtitle = subtitle.map(Text.init)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.relatedControlSpacing) {
            SettingsPageBackButton()
            heading
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.largeTitle.bold())
            if let subtitle {
                subtitle
                    #if os(tvOS)
                    .font(SettingsRowMetrics.helperFont)
                    #else
                    .font(.subheadline)
                    #endif
                    .plozzForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
