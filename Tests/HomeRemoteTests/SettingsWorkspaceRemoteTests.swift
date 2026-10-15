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
        let language = app.staticTexts["Language"].firstMatch
        let languageMenu = app.buttons["settings-group-language"].firstMatch
        XCTAssertTrue(languageMenu.exists, app.debugDescription)
        XCTAssertEqual(language.frame.midY, languageMenu.frame.midY, accuracy: 3)
        XCTAssertLessThanOrEqual(languageMenu.frame.height, 80, "Language must remain a compact single row.")
        XCTAssertFalse(app.staticTexts["Theme"].exists)
        XCTAssertFalse(app.buttons["settings-page-theme"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "System prompts and the player's own"
        )).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "The language Plozz uses for its own labels"
        )).firstMatch.exists)
        capture("01-general", in: app)
        try enterAndReturn("general", in: app)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(section("myLibraries", in: app).isSelected, app.debugDescription)

        for (index, name) in [
            "myLibraries", "appearance", "playback", "subtitles", "liveTV", "integrations",
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
        XCTAssertTrue(app.staticTexts["Audio"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["settings-page-subtitles"].exists)
        XCTAssertFalse(app.staticTexts["Show subtitles"].exists)
        capture("19-playback-entered", in: app)
        XCTAssertFalse(app.buttons["settings-section-general"].exists, app.debugDescription)
        XCUIRemote.shared.press(.menu)
        try focus(section("subtitles", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Show subtitles"].waitForExistence(timeout: 5), app.debugDescription)
        capture("20-subtitles", in: app)
        let style = app.buttons["Customize subtitle style"]
        try focus(style, in: app)
        capture("subtitles-lower", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Back"))
            .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        capture("subtitle-style", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(style.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(hasFocus(section("subtitles", in: app)), app.debugDescription)
        #else
        throw XCTSkip("Never seeds or changes settings on a physical device.")
        #endif
    }

    func testAppearancePagesAndNavigationStyleChanges() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings()
        defer { capture("appearance-final-state", in: app) }
        try focus(section("appearance", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let theme = app.buttons["settings-page-theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5), app.debugDescription)
        try focus(theme, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Gradient Backgrounds"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Liquid Glass")).firstMatch.exists,
                      app.debugDescription)
        capture("theme", in: app)
        XCUIRemote.shared.press(.menu)
        try focus(app.buttons["settings-page-home"], in: app)
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
            XCTAssertFalse(section("appearance", in: app).exists)
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
                XCTAssertTrue(app.buttons["settings-category-back"].exists, "Unlock must stay in the category.")
                XCTAssertFalse(section("myLibraries", in: app).exists)
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
        let app = try launchSettings(style: "tabBar")
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
        try focus(app.buttons["settings-page-home"], in: app)
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

    func testCompactIPTVSourcesAndChildBackNavigation() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar", sources: true)
        defer { capture("compact-final-state", in: app) }
        try focus(section("metadata", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let recommended = app.buttons["Recommended"]
        XCTAssertTrue(recommended.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThanOrEqual(recommended.frame.height, 66)
        capture("compact-metadata-options", in: app)
        XCUIRemote.shared.press(.menu)
        try focus(section("liveTV", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertLessThan(
            app.staticTexts["Preview the focused channel as you browse."].firstMatch.frame.height,
            app.staticTexts["Auto preview"].firstMatch.frame.height,
            "Helper text must render smaller than the control label, not just use a different text style."
        )
        capture("compact-guide-settings", in: app)
        try focus(app.buttons["settings-page-sources"], in: app)
        XCUIRemote.shared.press(.select)
        let first = app.buttons["live-tv-source-details-settings-review-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        for index in 0..<6 {
            let row = app.buttons["live-tv-source-details-settings-review-\(index)"]
            XCTAssertTrue(row.exists)
            XCTAssertLessThanOrEqual(row.frame.height, 110, "Sources must be compact summary rows.")
        }
        XCTAssertFalse(app.buttons["live-tv-remove-source-settings-review-0"].exists)
        capture("compact-iptv-sources", in: app)
        try focus(app.buttons["live-tv-add-server"], in: app)
        capture("iptv-sources-scrolled", in: app)
        let detailScroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first {
            $0.buttons["live-tv-add-server"].exists
        })
        XCTAssertLessThanOrEqual(detailScroll.frame.minY, 1, "The scroll viewport must reach the screen edge.")
        let detailMaxX = detailScroll.frame.maxX
        try focus(first, in: app)
        XCUIRemote.shared.press(.select)
        let back = pageBack("live-tv-settings-back", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Northstar TV"].exists)
        capture("iptv-source-controls", in: app)
        for link in [
            "live-tv-edit-source-settings-review-0",
            "live-tv-source-guides-settings-review-0"
        ] {
            try focus(app.buttons[link], in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
            if link == "live-tv-source-guides-settings-review-0" {
                for identifier in ["live-tv-guide-lookback", "live-tv-guide-lookahead"] {
                    let menu = app.buttons[identifier]
                    XCTAssertTrue(menu.exists)
                    XCTAssertLessThanOrEqual(menu.frame.maxX, detailMaxX - 28)
                }
            }
            capture(link, in: app)
            try focus(back, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons[link].waitForExistence(timeout: 5), app.debugDescription)
        }
        try focus(back, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(first.waitForExistence(timeout: 5), app.debugDescription)
        #else
        throw XCTSkip("Never seeds sources on a physical device.")
        #endif
    }

    func testSubtitleStyleEditorsExpandAndRestoreTheWorkspace() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        defer { capture("subtitle-fullscreen-final-state", in: app) }
        try focus(section("subtitles", in: app), in: app)
        XCUIRemote.shared.press(.select)
        let primaryStyle = app.buttons["Customize subtitle style"]
        XCTAssertTrue(primaryStyle.isHittable, "Subtitle style must be visible near the top without scrolling.")
        XCTAssertLessThan(primaryStyle.frame.minY, app.staticTexts["Subtitle language"].firstMatch.frame.minY)
        for (title, captureName) in [
            ("Customize subtitle style", "subtitle-style"),
            ("Customize Live TV subtitles", "subtitle-style-live-tv")
        ] {
            if title == "Customize Live TV subtitles", !app.buttons[title].exists {
                let separateStyle = app.switches["Use a separate style for Live TV"]
                try focus(separateStyle, in: app)
                XCUIRemote.shared.press(.select)
            }
            let link = app.buttons[title]
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
            try focus(link, in: app)
            capture("\(captureName)-before", in: app)
            XCUIRemote.shared.press(.select)
            let heading = app.staticTexts[title]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("subtitles", in: app).exists, app.debugDescription)
            XCTAssertFalse(app.buttons["settings-profile-switch"].exists)
            XCTAssertLessThan(heading.frame.minX, 200, "The editor must reclaim the sidebar column.")
            let back = pageBack(in: app)
            let controlColumn = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first {
                $0.buttons["settings-workspace-back"].exists
            }, "The editor's Back button must belong to its scrolling control column.")
            XCTAssertTrue(controlColumn.staticTexts[title].exists,
                          "The page heading must scroll with its controls, not occupy a fixed header.")
            XCTAssertLessThanOrEqual(controlColumn.frame.minY, 1,
                                     "The page scroll viewport must reach the top screen edge.")
            let preview = app.otherElements["subtitle-style-preview"]
            XCTAssertTrue(preview.exists)
            let previewAtEntry = preview.frame
            XCTAssertTrue(back.exists)
            XCTAssertGreaterThanOrEqual(back.frame.minY, controlColumn.frame.minY,
                                        "The scrolling viewport must not crop Back at page entry.")
            let editorCard = app.otherElements["subtitle-style-editor-card"]
            XCTAssertTrue(editorCard.exists)
            XCTAssertFalse(editorCard.buttons["settings-workspace-back"].exists,
                           "Page navigation belongs outside the Appearance card.")
            capture(captureName, in: app)
            let font = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Font")).firstMatch
            let matchedSystemStyle = !font.isEnabled
            let matchSystemStyle = app.buttons["Match Apple TV Subtitle Style"]
            if matchedSystemStyle {
                try focus(matchSystemStyle, in: app)
                XCUIRemote.shared.press(.select)
            }
            try focus(font, in: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Font"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("subtitles", in: app).exists)
            try focus(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "System Fonts")).firstMatch,
                      in: app)
            XCTAssertLessThanOrEqual(heading.frame.maxY, controlColumn.frame.minY,
                                    "Browsing fonts must scroll the entire page title out of the viewport.")
            XCTAssertEqual(preview.frame.minY, previewAtEntry.minY, accuracy: 1)
            XCTAssertEqual(preview.frame.width, previewAtEntry.width, accuracy: 1)
            XCTAssertEqual(preview.frame.height, previewAtEntry.height, accuracy: 1)
            capture("\(captureName)-fonts", in: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5), app.debugDescription)
            if matchedSystemStyle {
                try focus(matchSystemStyle, in: app)
                XCUIRemote.shared.press(.select)
            }
            if title == "Customize subtitle style" {
                XCUIRemote.shared.press(.menu)
            } else {
                let back = pageBack(in: app)
                try focus(back, in: app)
                XCUIRemote.shared.press(.select)
            }
            XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(section("subtitles", in: app).exists)
            XCTAssertFalse(app.buttons["settings-profile-switch"].exists)
            XCTAssertTrue(app.buttons["settings-category-back"].exists)
            capture("\(captureName)-returned", in: app)
        }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(hasFocus(section("subtitles", in: app)), app.debugDescription)
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    func testAlignedIdentityHeadersAndCompactDetailPageControls() throws {
        #if targetEnvironment(simulator)
        let app = try launchSettings(style: "tabBar")
        let profile = app.staticTexts["settings-profile-name"]
        let everyone = app.staticTexts["settings-everyone-name"]
        XCTAssertTrue(profile.exists && everyone.exists, app.debugDescription)
        XCTAssertEqual(profile.frame.minX, everyone.frame.minX, accuracy: 2)
        XCTAssertEqual(profile.frame.height, everyone.frame.height, accuracy: 2)
        XCTAssertLessThanOrEqual(profile.frame.height, 46)
        capture("aligned-settings-headers", in: app)

        try focus(section("appearance", in: app), in: app)
        XCUIRemote.shared.press(.select)
        try focus(app.buttons["settings-page-title-details"], in: app)
        XCUIRemote.shared.press(.select)
        let showScores = app.switches["Show review scores"]
        XCTAssertTrue(showScores.waitForExistence(timeout: 5), app.debugDescription)
        let back = pageBack(in: app)
        XCTAssertTrue(back.exists)
        let scroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first {
            $0.buttons["settings-workspace-back"].exists
        }, "Back must be inside the page scroll view, not overlaid above it.")
        capture("detail-page-scrolling-back", in: app)
        try focus(showScores, in: app)
        let countLabel = app.staticTexts.matching(NSPredicate(
            format: "label ==[c] %@", "Maximum ratings shown"
        )).firstMatch
        XCTAssertTrue(countLabel.exists, app.debugDescription)
        XCTAssertGreaterThan(countLabel.frame.minY, showScores.frame.maxY)
        XCTAssertLessThanOrEqual(countLabel.frame.minY - showScores.frame.maxY, 40,
                                "Related review-score controls must use the compact shared gap.")
        capture("compact-review-score-controls", in: app)
        let age = app.switches["Show Common Sense age"]
        try focus(age, in: app)
        XCTAssertTrue(scroll.buttons["settings-workspace-back"].exists)
        capture("detail-page-scrolled", in: app)
        try focus(back, in: app)
        capture("detail-page-back-returned", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["settings-page-title-details"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Simulator-only Settings review.")
        #endif
    }

    private func launchSettings(
        style: String = "rail", profile: String = "Alex", kids: String = "off",
        diagnostics: Bool = false, sources: Bool = false
    ) throws -> XCUIApplication {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLOZZ_SETTINGS_REVIEW"] == "1",
            "Requires the production app installed on a task-owned simulator."
        )
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz")
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS"] = "1"
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_NAVIGATION"] = style
        app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_KIDS"] = kids
        if sources {
            app.launchEnvironment["PLOZZ_SHOTS_SETTINGS_SOURCES"] = try XCTUnwrap(
                ProcessInfo.processInfo.environment["PLOZZ_SETTINGS_SOURCE_ORIGIN"],
                "Source review requires an owned loopback fixture server."
            )
        }
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
        let keepPreviewsOff = app.buttons["live-tv-preview-disable"]
        if keepPreviewsOff.waitForExistence(timeout: 2) {
            try focus(keepPreviewsOff, in: app)
            XCUIRemote.shared.press(.select)
        }
        if sources { capture("source-fixture-entry", in: app) }
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
            predicate: NSPredicate { _, _ in
                !selected.exists && !other.exists && app.buttons["settings-category-back"].exists
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 4), .completed,
                       "Native focus did not enter \(route). \(app.debugDescription)")
        capture("editing-\(route)", in: app)
        if usingRight {
            try focus(app.buttons["settings-category-back"], in: app)
            XCUIRemote.shared.press(.select)
        } else {
            XCUIRemote.shared.press(.menu)
        }
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in selected.isSelected && other.isEnabled },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 4), .completed,
                       "Native focus did not return from \(route). \(app.debugDescription)")
    }

    private func focus(_ target: XCUIElement, in app: XCUIApplication) throws {
        guard target.waitForExistence(timeout: 5) else {
            XCTFail("Missing focus target. \(app.debugDescription)")
            return
        }
        var requestedNavigation = false
        for _ in 0..<35 {
            if hasFocus(target) { return }
            let nativeFocused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true AND enabled == true")).firstMatch
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
            let fullWidthSettings = pageBack("settings-category-back", in: app).exists
                || pageBack(in: app).exists || pageBack("live-tv-settings-back", in: app).exists
            let sameDetail = fullWidthSettings
                || (general.exists && from.minX > general.frame.maxX && to.minX > general.frame.maxX)
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
        guard target.exists, target.isEnabled else { return false }
        return target.hasFocus || target.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
    }

    private func pageBack(_ identifier: String = "settings-workspace-back", in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: identifier)
            .matching(NSPredicate(format: "enabled == true")).firstMatch
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
