import CoreModels
import CoreUI
import FeatureAuth
import FeatureAuthCore
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class AccountRecoveryPresentationHostedTests: XCTestCase {
    func testPlexRecoveryKeepsExplanationAndAllActionsVisibleWithNativePrimaryFocus() async throws {
        for (name, error) in [("expired", AppError.unauthorized), ("offline", .serverUnreachable)] {
            try await verify(
                PlexAccountRecoveryView(
                    name: "Alex", message: error.userMessage, signIn: nil,
                    onSignIn: {}, onRetry: {}, onCancel: {}, onCancelSignIn: {}
                ),
                name: "Plex recovery \(name)", palette: .dark,
                expected: ["Reconnect to Plex", "Alex", "Sign In Again", "Try Again", "Cancel"],
                focusedTitle: "Sign In Again"
            )
        }
    }

    func testManagedAccountErrorsShareRecoveryLayoutAcrossProvidersAndThemes() async throws {
        for provider in ProviderKind.allCases where provider.supportsAccountReauthentication {
            let account = Account(
                id: "account",
                server: MediaServer(
                    id: "server", name: "Home Server",
                    baseURL: try XCTUnwrap(URL(string: "https://server.example")), provider: provider
                ),
                userID: "alex", userName: "Alex", deviceID: "fixture"
            )
            for (theme, palette) in [("dark", ThemePalette.dark), ("light", .light)] {
                let model = AccountReauthenticationModel(
                    account: account, deviceID: "fixture",
                    store: AccountStore(secureStore: InMemorySecureStore()),
                    isAuthorized: { true }, onComplete: { XCTFail("Mismatched sign-in must not complete.") }
                )
                var session = account.session(token: "FIXTURE")
                session.userID = "different-user"
                XCTAssertThrowsError(try model.complete(session))
                try await verify(
                    AccountReauthenticationView(model: model, onCancel: {}) { _ in EmptyView() },
                    name: "\(provider.displayName) recovery \(theme)", palette: palette,
                    expected: ["Reconnect to \(provider.displayName)", "Alex", "same account", "Try Again", "Cancel"],
                    focusedTitle: "Try Again"
                )
            }
        }
    }

    func testPlaybackFailureRetainsReadableExplanationAndActionsInSharedLayout() async throws {
        try await verify(
            PlaybackFailureView(
                title: "Playback timed out", message: AppError.serverUnreachable.userMessage, report: nil
            ) {
                Button("Try Again") {}.plozzActionButton()
                Button("Back") {}.plozzActionButton(role: .secondary)
            },
            name: "Playback recovery", palette: .light,
            expected: ["Playback timed out", "server", "Try Again", "Back"]
        )
    }

    private func verify<Content: View>(
        _ content: Content, name: String, palette: ThemePalette,
        expected: [String], focusedTitle: String? = nil
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        #if os(iOS)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        #endif
        let host = UIHostingController(rootView:
            ZStack {
                AppBackground(palette: palette).ignoresSafeArea()
                content
            }
            .environment(\.themePalette, palette)
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.dynamicTypeSize, .large)
        )
        host.overrideUserInterfaceStyle = palette.isLight ? .light : .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        #if os(tvOS)
        let focus = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
        let focusDeadline = ContinuousClock.now + .seconds(5)
        while focus.focusedItem == nil, ContinuousClock.now < focusDeadline {
            focus.requestFocusUpdate(to: host)
            focus.updateFocusIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #endif
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let observations = request.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        for value in expected {
            XCTAssertTrue(text.contains(value), "\(name) must show \(value): \(text)")
        }
        let safeBounds = window.bounds.inset(by: window.safeAreaInsets)
        for observation in observations {
            let rect = observation.boundingBox
            let frame = CGRect(
                x: rect.minX * window.bounds.width, y: (1 - rect.maxY) * window.bounds.height,
                width: rect.width * window.bounds.width, height: rect.height * window.bounds.height
            )
            XCTAssertTrue(safeBounds.contains(frame), "\(name) text must remain inside the safe area: \(frame)")
        }
        #if os(tvOS)
        if let focusedTitle {
            let item = try XCTUnwrap(focus.focusedItem)
            var environment: (any UIFocusEnvironment)? = item
            var focusedFrame: CGRect?
            while let current = environment {
                if let container = current.focusItemContainer {
                    focusedFrame = container.coordinateSpace.convert(item.frame, to: window)
                    break
                }
                environment = current.parentFocusEnvironment
            }
            let frame = try XCTUnwrap(focusedFrame)
            XCTAssertTrue(observations.contains { observation in
                guard observation.topCandidates(1).first?.string == focusedTitle else { return false }
                let rect = observation.boundingBox
                return frame.contains(CGPoint(
                    x: rect.midX * window.bounds.width, y: (1 - rect.midY) * window.bounds.height
                ))
            }, "Native focus must land on \(focusedTitle), not just a SwiftUI focus binding: \(text)")
        }
        #endif
    }
}
