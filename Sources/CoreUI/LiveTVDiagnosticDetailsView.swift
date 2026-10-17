#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct LiveTVDiagnosticDetailsView: View {
    public let report: LiveTVDiagnosticReport

    public init(report: LiveTVDiagnosticReport) { self.report = report }

    private var supportText: String { // l10n:content — technical support report
        let version = AppVersionIdentity.current
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(tvOS)
        let platform = "tvOS"
        #elseif os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        return report.supportText
            + "\napp_version=\(version.displayVersion)\napp_build=\(version.build)"
            + "\nplatform=\(platform)\nos_version=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let message = report.message {
                    Text(message).font(.body)
                }
                Text("Sharing this report is optional. It contains no addresses, credentials, account names, or channel names.")
                    .font(.callout)
                Text(verbatim: supportText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                    .textSelection(.enabled)
                    #elseif os(tvOS)
                    .focusable()
                    #endif
                    .accessibilityIdentifier("live-tv-diagnostic-report")
                #if os(iOS)
                ShareLink(item: supportText) { Label("Share details", systemImage: "square.and.arrow.up") }
                #endif
            }
            .frame(maxWidth: 1_000, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Details")
        .background { SettingsPageBackground() }
    }
}

public struct LiveTVDiagnosticDetailsSheet: View {
    private let report: LiveTVDiagnosticReport
    @Environment(\.dismiss) private var dismiss

    public init(report: LiveTVDiagnosticReport) { self.report = report }

    public var body: some View {
        NavigationStack {
            LiveTVDiagnosticDetailsView(report: report)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
#endif
