import CoreUI
import FeatureLiveTVCore
import SwiftUI

#if os(iOS)
import UIKit

struct PrototypeSearchHeader: View {
    @Binding var query: String
    let channelCount: Int
    let category: String?
    let focusRequest: Int
    let browse: () -> Void
    let close: () -> Void
    let focusChanged: (Bool) -> Void
    var showsSummary = true

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            PrototypeMobileSearchField(
                query: $query, focusRequest: focusRequest,
                submit: browse, cancel: close, focusChanged: focusChanged
            )
            .frame(height: 56)
            if showsSummary {
                PrototypeSearchSummary(channelCount: channelCount, category: category)
            }
        }
    }
}

private struct PrototypeMobileSearchField: UIViewRepresentable {
    @Binding var query: String
    let focusRequest: Int
    let submit: () -> Void
    let cancel: () -> Void
    let focusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = String(localized: "Search")
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .no
        bar.searchTextField.accessibilityIdentifier = "live-tv-search-field"
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != query { bar.text = query }
        if focusRequest > context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak bar] in
                guard let bar, bar.window != nil else { return }
                bar.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: PrototypeMobileSearchField
        var focusRequest = 0
        init(_ parent: PrototypeMobileSearchField) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.query = searchText
        }
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
            parent.focusChanged(true)
        }
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(false, animated: true)
            parent.focusChanged(false)
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.submit()
        }
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.query = ""
            searchBar.resignFirstResponder()
            parent.cancel()
        }
    }
}
#endif

struct PrototypeCategorySearchResults: View {
    let categories: [LiveTVBrowseCategory]
    let select: (String) -> Void
    @Environment(\.themePalette) private var palette
    #if os(tvOS)
    @ScaledMetric(relativeTo: .headline) private var tileHeight: CGFloat = 128
    #else
    @ScaledMetric(relativeTo: .headline) private var tileHeight: CGFloat = 68
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            Text("Categories")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            ScrollView(.horizontal) {
                LazyHStack(spacing: PrototypeLayout.gap) {
                    ForEach(categories) { category in
                        PrototypeCategoryTile(name: category.name, count: category.channelCount) {
                            select(category.name)
                        }
                        .frame(width: PrototypeCategoryTile.searchWidth)
                        .accessibilityIdentifier("live-tv-search-category-\(category.name)")
                    }
                }
                .padding(PrototypeLayout.gap)
            }
            .scrollIndicators(.hidden)
            .frame(height: tileHeight + PrototypeLayout.gap * 4)
            .padding(.horizontal, -PrototypeLayout.gap)
        }
        .accessibilityIdentifier("live-tv-search-categories")
    }
}

private struct PrototypeSearchResultsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var prototypeSearchResults: Bool {
        get { self[PrototypeSearchResultsKey.self] }
        set { self[PrototypeSearchResultsKey.self] = newValue }
    }
}

struct PrototypeSearchResults<Content: View>: View {
    let content: Content
    var body: some View { content.environment(\.prototypeSearchResults, true) }
}

struct PrototypeSearchFocusBoundary<Content: View>: View {
    @Environment(\.prototypeSearchResults) private var isSearchResult
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(tvOS)
        if isSearchResult {
            PrototypeSearchRowHost(content: content())
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

#if os(tvOS)
import UIKit

/// Give native Search a row-sized focused UIView, not the entire lazy stack.
/// Its keyboard-collapse scrolling still runs unchanged using this real boundary.
struct PrototypeSearchRowHost<Content: View>: UIViewControllerRepresentable {
    let content: Content

    struct HostedContent: View {
        let content: Content
        let environment: EnvironmentValues
        var body: some View { content.environment(\.self, environment) }
    }

    func makeUIViewController(context: Context) -> UIHostingController<HostedContent> {
        let controller = UIHostingController(rootView: HostedContent(content: content, environment: context.environment))
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<HostedContent>, context: Context) {
        controller.rootView = HostedContent(content: content, environment: context.environment)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiViewController: UIHostingController<HostedContent>, context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiViewController.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
    }
}
#endif
