#if os(tvOS)
import TVServices

/// Shared by the extension and tests, without the app's model or artwork stack.
public enum TopShelfContentBuilder {
    public static func makeContent(from snapshot: TopShelfSnapshot) -> (any TVTopShelfContent)? {
        if snapshot.usesFullScreen {
            var seen = Set<String>()
            let items = snapshot.sections.flatMap { section in
                section.items.compactMap { item -> TVTopShelfCarouselItem? in
                    guard seen.insert(item.shelfIdentifier).inserted else { return nil }
                    let result = TVTopShelfCarouselItem(identifier: item.shelfIdentifier)
                    configure(result, from: item)
                    result.contextTitle = [section.title, item.subtitle].compactMap { $0 }.joined(separator: " · ")
                    result.summary = item.summary
                    result.genre = item.genre
                    if let duration = item.duration, duration.isFinite, duration > 0 {
                        result.duration = duration
                    }
                    return result
                }
            }
            return items.isEmpty ? nil : TVTopShelfCarouselContent(style: .details, items: items)
        }

        let sections = snapshot.sections.compactMap { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? in
            guard !section.items.isEmpty else { return nil }
            let items = section.items.map { item in
                let result = TVTopShelfSectionedItem(identifier: item.shelfIdentifier)
                configure(result, from: item)
                result.imageShape = .poster
                result.displayAction = result.playAction
                return result
            }
            let result = TVTopShelfItemCollection(items: items)
            result.title = section.title
            return result
        }
        return sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections)
    }

    private static func configure(_ result: TVTopShelfItem, from item: TopShelfSnapshot.Item) {
        result.title = item.title
        if let imageURL = item.imageURL {
            result.setImageURL(imageURL, for: .screenScale1x)
            result.setImageURL(imageURL, for: .screenScale2x)
        }
        result.playAction = TVTopShelfAction(url: TopShelf.itemDeepLink(id: item.id, accountID: item.accountID))
    }
}
#endif
