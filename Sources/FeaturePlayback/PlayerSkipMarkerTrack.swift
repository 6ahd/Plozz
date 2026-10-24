#if canImport(SwiftUI)
import CoreModels
import CoreNetworking
import SwiftUI

enum SkipMarkerTrackLayout {
    static func ranges(segments: [MediaSegment], duration: TimeInterval) -> [Range<Double>] {
        guard duration.isFinite, duration > 0 else { return [] }
        var malformed = 0
        let ranges = segments.compactMap { segment -> Range<Double>? in
            guard segment.isSkippable else { return nil }
            guard segment.start.isFinite, segment.end.isFinite, segment.end > segment.start else {
                malformed += 1
                return nil
            }
            let start = max(0, segment.start)
            let end = min(duration, segment.end)
            guard start < end else { return nil }
            return (start / duration)..<(end / duration)
        }.sorted { $0.lowerBound < $1.lowerBound }
        if malformed > 0 {
            PlozzLog.app.debug("Ignored \(malformed) skip-marker range(s) with invalid timing")
        }
        var merged: [Range<Double>] = []
        for range in ranges {
            if let previous = merged.last, range.lowerBound <= previous.upperBound {
                merged[merged.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func segmentedSections(
        ranges: [Range<Double>], size: CGSize, minimumSectionWidth: CGFloat = 0
    ) -> [CGRect] {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return [] }
        var boundaries: [CGFloat] = [0]
        for range in ranges {
            for fraction in [range.lowerBound, range.upperBound] where fraction > 0 && fraction < 1 {
                boundaries.append(size.width * CGFloat(fraction))
            }
        }
        boundaries.append(size.width)
        let maximumHalfGap: CGFloat = 2
        if minimumSectionWidth > 0 {
            // Inspect the original neighbors, including unmarked intervals. Removing
            // both cuts around a tiny piece avoids replacing it with a misleading
            // enlarged segment or a cut through its center.
            let minimumInterval = minimumSectionWidth + 2 * maximumHalfGap
            boundaries = boundaries.indices.compactMap { index in
                guard index > 0, index < boundaries.count - 1 else { return boundaries[index] }
                guard boundaries[index] - boundaries[index - 1] >= minimumInterval,
                      boundaries[index + 1] - boundaries[index] >= minimumInterval else { return nil }
                return boundaries[index]
            }
        }
        let halfGaps = boundaries.indices.map { index -> CGFloat in
            guard index > 0, index < boundaries.count - 1 else { return 0 }
            // Keep gaps centered on their time boundary without consuming tiny sections.
            return min(maximumHalfGap, min(
                (boundaries[index] - boundaries[index - 1]) / 4,
                (boundaries[index + 1] - boundaries[index]) / 4
            ))
        }
        return boundaries.indices.dropLast().map { index in
            let start = boundaries[index] + halfGaps[index]
            let end = boundaries[index + 1] - halfGaps[index + 1]
            return CGRect(x: start, y: 0, width: end - start, height: size.height)
        }
    }

    static func boundaryCornerRadius(leftWidth: CGFloat, rightWidth: CGFloat, height: CGFloat) -> CGFloat {
        let available = min(1, min(leftWidth, rightWidth) / height)
        // Both sides of a tight cut flatten together; roomy sections retain full caps.
        return height / 2 * available * available
    }

    static func maskPath(
        ranges: [Range<Double>], size: CGSize, minimumSectionWidth: CGFloat = 0
    ) -> Path {
        let sections = segmentedSections(ranges: ranges, size: size, minimumSectionWidth: minimumSectionWidth)
        var mask = Path()
        for index in sections.indices {
            let section = sections[index]
            let outerRadius = min(section.width, section.height) / 2
            let leading = index == 0 ? outerRadius : boundaryCornerRadius(
                leftWidth: sections[index - 1].width, rightWidth: section.width, height: section.height
            )
            let trailing = index == sections.count - 1 ? outerRadius : boundaryCornerRadius(
                leftWidth: section.width, rightWidth: sections[index + 1].width, height: section.height
            )
            if leading == trailing {
                mask.addRoundedRect(in: section, cornerSize: CGSize(width: leading, height: leading))
            } else {
                mask.addPath(UnevenRoundedRectangle(
                    topLeadingRadius: leading, bottomLeadingRadius: leading,
                    bottomTrailingRadius: trailing, topTrailingRadius: trailing, style: .circular
                ).path(in: section))
            }
        }
        return mask
    }
}

/// Splits all three progress fills at legible skip boundaries without changing timing.
struct PlayerSkipMarkerTrack: View, Equatable {
    let segments: [MediaSegment]
    let duration: TimeInterval
    let height: CGFloat
    var minimumSectionWidth: CGFloat = 0

    var body: some View {
        let ranges = SkipMarkerTrackLayout.ranges(segments: segments, duration: duration)
        Canvas { context, size in
            let mask = SkipMarkerTrackLayout.maskPath(
                ranges: ranges, size: size, minimumSectionWidth: minimumSectionWidth
            )
            context.fill(mask, with: .color(.white))
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#endif
