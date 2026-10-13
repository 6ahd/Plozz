import CoreModels
@testable import CoreUI
import SwiftUI
import TVUIKit
import UIKit
import XCTest

@MainActor
final class HomeLiveTVCardHostedTests: XCTestCase {
    func testNativeFocusPreservesDarkChannelSurfaceGeometryAndTuneAction() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var focused: [String] = []
        var selected: [HomeLiveTVRoute] = []
        let channels = (0..<3).map { index in
            HomeLiveTVChannel(
                route: .init(
                    profileID: "profile", channelID: "channel-\(index)", sourceID: "source",
                    sourceAuthorizationID: "approval", serverAuthorizationID: "server"
                ), name: "Channel \(index)", sourceName: "My channels", number: index + 1
            )
        }
        let host = HomeChannelFocusHost(rootView: AnyView(
            HStack(spacing: 50) {
                ForEach(channels) { channel in
                    HomeLiveTVCard(channel: channel, width: 480) { focused.append($0.route.channelID) }
                }
            }
            .environment(\.plozzCardFocusStyle, .system)
            .environment(\.themePalette, .dark)
            .environment(\.openHomeLiveTV, { selected.append($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.target = nil
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let cards = nativeCards(in: window).sorted {
            $0.convert($0.bounds, to: window).minX < $1.convert($1.bounds, to: window).minX
        }
        XCTAssertEqual(cards.count, 3, "Live TV must use the same native card owner as the other Home cards.")
        let original = cards.map { $0.superview?.frame }
        for (index, card) in cards.enumerated() {
            host.target = card
            host.setNeedsFocusUpdate()
            host.updateFocusIfNeeded()
            let deadline = ContinuousClock.now + .seconds(3)
            while !card.isFocused, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(card.isFocused)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(focused.last, channels[index].route.channelID, "Native focus must still update the Home hero.")
            XCTAssertEqual(cards.map { $0.superview?.frame }, original, "Focus must not resize or shift layout slots.")
            XCTAssertEqual(card.contentSize.width, 480, accuracy: 0.5)
            XCTAssertEqual(card.contentSize.height, 270, accuracy: 0.5)
            let frame = try XCTUnwrap(NativeFocusProjection.artworkFrame(of: card.contentView, in: window))
            for other in cards where other !== card {
                let neighbor = try XCTUnwrap(NativeFocusProjection.artworkFrame(of: other.contentView, in: window))
                XCTAssertTrue(frame.intersection(neighbor).isNull, "Native focus must leave the neighboring card clear.")
            }
            let image = DetailTransitionSnapshot.image(of: window)
            let point = CGPoint(x: frame.minX + frame.width * 0.85, y: frame.minY + frame.height * 0.9)
            let pixel = try sample(image, at: point)
            XCTAssertLessThan(max(pixel[0], pixel[1], pixel[2]), 170, "Focus must not replace the dark card with white.")
            try assertNativeSurfaceOwnsCorners(of: card)
            let attachment = XCTAttachment(image: image)
            attachment.name = "home-live-channel-native-focus-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let last = try XCTUnwrap(cards.last)
        last.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(selected, [channels[2].route], "Select must send the original authorized tune route once.")
    }

    private func assertNativeSurfaceOwnsCorners(of card: TVCardView) throws {
        let label = try XCTUnwrap(card.contentView.subviews.first { $0 is any UIContentView })
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { context in
            label.layer.render(in: context.cgContext)
        }
        var maximumAlpha: UInt8 = 0
        for x in [CGFloat(2), 8, 16, label.bounds.width - 16, label.bounds.width - 8, label.bounds.width - 2] {
            for y in [CGFloat(2), 8, 16, label.bounds.height - 16, label.bounds.height - 8, label.bounds.height - 2] {
                maximumAlpha = max(maximumAlpha, try sample(image, at: CGPoint(x: x, y: y))[3])
            }
        }
        XCTAssertEqual(maximumAlpha, 0, "The hosted label must not paint a second surface or border inside TVCardView's corners.")
    }

    private func nativeCards(in view: UIView) -> [TVCardView] {
        (view as? TVCardView).map { [$0] } ?? view.subviews.flatMap(nativeCards(in:))
    }

    private func sample(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(
            x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1
        )))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }
}

@MainActor
private final class HomeChannelFocusHost: UIHostingController<AnyView> {
    weak var target: UIView?
    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        target.map { [$0] } ?? super.preferredFocusEnvironments
    }
}
