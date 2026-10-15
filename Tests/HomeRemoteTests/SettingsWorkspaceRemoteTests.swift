import XCTest

@MainActor
final class SettingsWorkspaceRemoteTests: XCTestCase {
    func testSettingsSectionsAndNestedPagesInTheProductionApp() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { capture("final-state", in: app) }
        let general = section("general", in: app)
        XCTAssertTrue(general.isSelected, app.debugDescription)
        XCTAssertTrue(app.buttons["settings-profile-switch"].exists)
        XCTAssertTrue(app.buttons["settings-profile-edit"].exists)
        capture("01-general", in: app)
        try enterAndReturn("general", in: app)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(section("myLibraries", in: app).isSelected, app.debugDescription)

        for (index, name) in [
            "myLibraries", "appearance", "playback", "liveTV", "integrations",
            "servers", "profile", "parentalPIN", "seerr", "syncSetup", "metadata", "about", "help"
        ].enumerated() {
            let target = section(name, in: app)
            XCTAssertTrue(target.exists, "Missing Settings section: \(name)")
            try focus(target, in: app)
            XCTAssertTrue(hasFocus(target))
            capture(String(format: "%02d-%@", index + 2, name), in: app)
            try enterAndReturn(name, in: app, usingRight: index.isMultiple(of: 2))
        }
        try focus(section("playback", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let subtitles = app.buttons["settings-page-subtitles"]
        XCTAssertTrue(subtitles.waitForExistence(timeout: 5), app.debugDescription)
        capture("19-playback-entered", in: app)
        XCTAssertFalse(app.buttons["settings-section-general"].isEnabled, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Show subtitles"].waitForExistence(timeout: 5), app.debugDescription)
        capture("20-subtitles", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(subtitles.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(hasFocus(section("playback", in: app)), app.debugDescription)
        #else
        throw XCTSkip("Never seeds or changes settings on a physical device.")
        #endif
    }

    func testAppearancePagesAndNavigationStyleChanges() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        try focus(section("appearance", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Home Layout"].waitForExistence(timeout: 5), app.debugDescription)
        capture("customize-home", in: app)
        try focus(app.buttons["settings-page-home-rows-all"], in: app)
        XCUIRemote.shared.press(.select)
        capture("home-rows", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["settings-page-home-rows-all"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["settings-page-navigation"].waitForExistence(timeout: 5))
        try focus(app.buttons["settings-page-display-size"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout: 5), app.debugDescription)
        capture("display-size", in: app)
        XCUIRemote.shared.press(.menu)
        try focus(app.buttons["settings-page-artwork"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["artwork-customization"].waitForExistence(timeout: 5))
        capture("artwork", in: app)
        try focus(app.buttons["artwork-customization"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["view-customization-back"].waitForExistence(timeout: 5), app.debugDescription)
        capture("artwork-customization", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["artwork-customization"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        try focus(app.buttons["settings-page-cards"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["card-label-customization"].waitForExistence(timeout: 5))
        capture("cards", in: app)
        try focus(app.buttons["card-label-customization"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["view-customization-back"].waitForExistence(timeout: 5), app.debugDescription)
        capture("card-label-customization", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["card-label-customization"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        try focus(app.buttons["settings-page-navigation"], in: app)
        XCUIRemote.shared.press(.select)
        for style in ["Top Bar", "Sidebar", "Pinned Sidebar"] {
            let choice = app.buttons[style]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
            try focus(choice, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Prevent Accidental Exit"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(section("appearance", in: app).isSelected)
            capture("navigation-\(style)", in: app)
        }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["settings-page-navigation"].waitForExistence(timeout: 5), app.debugDescription)
        for (page, heading) in [
            ("music-player", "Music Player"), ("night-shift", "Circadian Mode"),
            ("title-details", "Detail Page")
        ] {
            let link = app.buttons["settings-page-\(page)"]
            try focus(link, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5), app.debugDescription)
            capture(page, in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testNativeSidebarAndTopBarEntryAndExit() throws {
        #if targetEnvironment(simulator)
        for style in ["sidebar", "tabBar"] {
            let app = try launchSettings(style: style)
            XCTAssertTrue(section("general", in: app).isSelected)
            capture("entry-\(style)", in: app)
            try enterAndReturn("general", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertFalse(section("general", in: app).exists, app.debugDescription)
            capture("exit-\(style)", in: app)
            try openSettingsIfNeeded(in: app)
            try enterAndReturn("general", in: app)
            app.terminate()
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testProfileEditorAndSwitcherShareTheWorkspace() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        try focus(app.buttons["settings-profile-edit"], in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["How this profile looks, and who can open it."].waitForExistence(timeout: 5))
        capture("profile-edit", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.buttons["settings-profile-switch"].isEnabled }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, app.debugDescription)
        try focus(app.buttons["settings-profile-switch"], in: app)
        XCUIRemote.shared.press(.select)
        let sam = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Sam")).firstMatch
        XCTAssertTrue(sam.waitForExistence(timeout: 5), app.debugDescription)
        capture("profile-switcher", in: app)
        try focus(sam, in: app)
        XCUIRemote.shared.press(.select)
        try openSettingsIfNeeded(in: app)
        XCTAssertEqual(app.buttons["settings-profile-switch"].value as? String, "Sam")
        XCTAssertTrue(section("general", in: app).isSelected)
        capture("profile-switched", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testKidsSettingsRequirePINOnlyWhenConfigured() throws {
        #if targetEnvironment(simulator)
        for mode in ["no-pin", "pin"] {
            let app = try launchSettings(profile: "Sam", kids: mode)
            XCTAssertFalse(section("servers", in: app).exists)
            XCTAssertFalse(section("metadata", in: app).exists)
            capture("kids-\(mode)", in: app)
            try focus(section("myLibraries", in: app), in: app)
            XCUIRemote.shared.press(.select)
            if mode == "pin" {
                XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 5), app.debugDescription)
                capture("kids-pin-required", in: app)
                XCUIRemote.shared.press(.menu)
                XCTAssertTrue(section("general", in: app).isEnabled)
                XCUIRemote.shared.press(.select)
                for digit in ["1", "2", "3", "4"] {
                    try focus(app.buttons[digit], in: app)
                    XCUIRemote.shared.press(.select)
                }
                let unlocked = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in !app.buttons["1"].exists }, object: nil
                )
                XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 5), .completed, app.debugDescription)
                XCTAssertTrue(section("myLibraries", in: app).exists, "Unlock must not dismiss Settings.")
                capture("kids-unlocked", in: app)
            }
            XCTAssertFalse(section("metadata", in: app).exists)
            XCTAssertFalse(section("servers", in: app).exists)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(section("general", in: app).isEnabled)
            app.terminate()
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testPlaybackLiveTVAndTrackerChildPages() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        for (category, pages) in [
            ("playback", ["skip-intros-mode"]),
            ("liveTV", ["sources", "hidden-channels"]),
            ("integrations", ["trakt", "simkl", "anilist", "mal", "lastfm"])
        ] {
            try focus(section(category, in: app), in: app)
            XCUIRemote.shared.press(.select)
            for page in pages {
                let link = app.buttons["settings-page-\(page)"]
                XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
                try focus(link, in: app)
                XCUIRemote.shared.press(.select)
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Back"))
                    .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
                capture("child-\(page)", in: app)
                XCUIRemote.shared.press(.menu)
                XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
            }
            for _ in 0..<9 { XCUIRemote.shared.press(.down) }
            capture("lower-\(category)", in: app)
            XCUIRemote.shared.press(.menu)
        }
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testUninstrumentedSettingsEntry() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(diagnostics: false)
        try enterAndReturn("general", in: app)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testHeroEditorsRemainInsideTheSettingsPane() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        try focus(section("appearance", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.select)
        let fullscreen = app.buttons["Fullscreen Hero"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        try focus(fullscreen, in: app)
        XCUIRemote.shared.press(.select)
        let hero = app.buttons["settings-page-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        try focus(hero, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["hero-settings-titles"].waitForExistence(timeout: 5))
        capture("hero", in: app)
        for (page, content) in [
            ("titles", "Hero content sources"), ("ratings", "Ratings"), ("trailers", "Trailers")
        ] {
            let link = app.buttons["hero-settings-\(page)"]
            try focus(link, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["view-customization-back"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[content].exists)
            capture("hero-\(page)", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(link.waitForExistence(timeout: 5))
        }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    private func launchSettings(style: String = "rail", profile: String = "Alex", kids: String = "off", diagnostics: Bool = false) throws -> XCUIApplication {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLOZZ_SETTINGS_REVIEW"] == "1",
            "Requires the production app installed on a task-owned simulator."
        )
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz")
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS"] = "1"
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_NAVIGATION"] = style
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_KIDS"] = kids
        if diagnostics { app.launchEnvironment["PLZHFOCUS"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.staticTexts["Choose Home layout for this profile"].waitForExistence(timeout: 2) {
            try focus(app.buttons["Continue"], in: app)
            XCUIRemote.shared.press(.select)
        }
        let alex = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", profile)).firstMatch
        if alex.waitForExistence(timeout: 2) {
            try focus(alex, in: app)
            XCUIRemote.shared.press(.select)
        }
        if app.staticTexts["Choose Home layout for this profile"].waitForExistence(timeout: 2) {
            try focus(app.buttons["Continue"], in: app)
            XCUIRemote.shared.press(.select)
        }
        try openSettingsIfNeeded(in: app)
        return app
    }

    private func openSettingsIfNeeded(in app: XCUIApplication) throws {
        let general = section("general", in: app)
        if !general.waitForExistence(timeout: 3) {
            XCTAssertEqual(app.state, .runningForeground, "Settings navigation requires the actual foreground app.")
            let settings = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
            try focus(settings, in: app)
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(general.waitForExistence(timeout: 20), app.debugDescription)
        try focus(general, in: app)
    }

    private func section(_ route: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["settings-section-\(route)"]
    }

    private func enterAndReturn(_ route: String, in app: XCUIApplication, usingRight: Bool = false) throws {
        let selected = section(route, in: app)
        let other = section(route == "general" ? "playback" : "general", in: app)
        XCUIRemote.shared.press(usingRight ? .right : .select)
        let arrived = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in selected.isEnabled && !other.isEnabled },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 4), .completed,
                       "Native focus did not enter \(route). \(app.debugDescription)")
        capture("editing-\(route)", in: app)
        XCUIRemote.shared.press(usingRight ? .left : .menu)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in selected.isSelected && other.isEnabled },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 4), .completed,
                       "Native focus did not return from \(route). \(app.debugDescription)")
    }

    private func focus(_ target: XCUIElement, in app: XCUIApplication) throws {
        var requestedNavigation = false
        for _ in 0..<35 {
            if hasFocus(target) { return }
            let nativeFocused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings-section-"))
                .allElementsBoundByIndex.first(where: \.isSelected)
            guard let focused = nativeFocused.exists ? nativeFocused : selected else {
                if !requestedNavigation && target.label == "Settings" {
                    XCUIRemote.shared.press(.menu)
                    requestedNavigation = true
                } else {
                    XCUIRemote.shared.press(.left)
                }
                continue
            }
            let from = focused.frame
            let to = target.frame
            let general = section("general", in: app)
            let sameDetail = general.exists && from.minX > general.frame.maxX && to.minX > general.frame.maxX
            if sameDetail && to.maxY <= from.minY {
                XCUIRemote.shared.press(.up)
            } else if sameDetail && to.minY >= from.maxY {
                XCUIRemote.shared.press(.down)
            } else if to.minX > from.maxX {
                XCUIRemote.shared.press(.right)
            } else if to.maxX < from.minX {
                XCUIRemote.shared.press(.left)
            } else {
                XCUIRemote.shared.press(to.midY < from.midY ? .up : .down)
            }
        }
        XCTFail("Could not focus \(target.identifier) \(target.label). \(app.debugDescription)")
    }

    private func hasFocus(_ target: XCUIElement) -> Bool {
        target.hasFocus || target.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        // Behavior is asserted separately; let the native animation finish for the image.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "settings-native-\(name)"
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "settings-native-\(name)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
