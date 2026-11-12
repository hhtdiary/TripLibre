import XCTest

/// The sample-day tutorial (issue #114): first launch offers it and lets you skip it, it can be replayed from
/// Settings and from the tip on Today, and nothing done in it reaches the diary.
final class TutorialFlowTests: HHTUITestCase {
    func testReplayFromSettingsWalksTheSampleDay() {
        openTutorialFromSettings()

        // 1. select the stop that has no name yet
        XCTAssertTrue(sampleStop.label.contains("Unnamed place"), "the sample stop starts unnamed: \(sampleStop.label)")
        sampleStop.tap()
        waitForNavigationTitle("Visit")   // the app's real Visit screen, on the sample day
        XCTAssertTrue(app.buttons["Name this place"].exists, "the real page offers to name the place")
        dismissSheet()

        // 2. name it
        let name = app.textFields["tutorialName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "name field")
        name.tap()
        name.typeText("Mings flat")
        next()

        // 3. category, 4. purpose, 5. mode: each shows up on the sample diary row
        chip("Friend / Family").tap()
        next()
        chip("Pick-up / drop-off").tap()
        XCTAssertTrue(row(containing: "Mings flat").label.contains("Pick-up / drop-off"), "the purpose shows on the stop")
        next()
        XCTAssertTrue(row(containing: "Car").waitForExistence(timeout: 5), "the trip starts as the wrong guess")
        chip("Walk").tap()
        XCTAssertTrue(app.buttons["Walk"].firstMatch.isSelected, "Walk is announced as chosen")
        next()

        // 6. a stop inference made up: removing it joins the two walks around it
        XCTAssertTrue(row(containing: "S 17th St").waitForExistence(timeout: 5), "the phantom stop is in the day")
        app.buttons["tutorialRemoveStop"].tap()
        XCTAssertTrue(row(containing: "S 17th St").waitForNonExistence(timeout: 5), "the phantom stop is gone")
        XCTAssertTrue(app.buttons["tutorialUndoRemove"].exists, "the removal can be undone")
        next()

        // 7. limits, 8. recap with the four labels
        XCTAssertTrue(text(containing: "GPS drifts").waitForExistence(timeout: 5), "tracking limits")
        next()
        XCTAssertTrue(text(containing: "You've got it!").waitForExistence(timeout: 5), "recap")
        for value in ["Mings flat", "Friend / Family", "Pick-up / drop-off", "Walk"] {
            XCTAssertTrue(element(labelContaining: value).exists, "recap shows \(value)")
        }
        next()

        // back in Settings, and the diary has none of it
        waitForNavigationTitle("Settings")
        dismissSheet()
        waitForNavigationTitle("Today")
        XCTAssertFalse(element(labelContaining: "Mings flat").exists, "nothing from the sample day is in the diary")
    }

    func testNextFillsInStepsLeftUntouched() {
        openTutorialFromSettings()
        for _ in 0..<7 { next() }
        XCTAssertTrue(text(containing: "You've got it!").waitForExistence(timeout: 5), "recap")
        for value in ["Mingming's Home", "Friend / Family", "Social", "Walk"] {
            XCTAssertTrue(element(labelContaining: value).exists, "recap shows the example \(value)")
        }
        app.buttons["Back"].tap()
        XCTAssertTrue(text(containing: "GPS drifts").waitForExistence(timeout: 5), "Back returns to the step before")
    }

    func testSkipLeavesTheTutorial() {
        openTutorialFromSettings()
        app.buttons["tutorialSkip"].tap()
        waitForNavigationTitle("Settings")
    }

    func testTodayTipOpensTheTutorialAndThenStaysAway() {
        showYesterday()
        let show = app.buttons["diaryTipShow"]
        reveal(show)   // it sits under the map and the day's cards, where the list hasn't built its rows yet
        show.tap()
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10), "tutorial opens from the tip")
        app.buttons["tutorialSkip"].tap()
        XCTAssertTrue(tripRows.firstMatch.waitForExistence(timeout: 5), "back on the day")
        XCTAssertFalse(show.exists, "the tip doesn't come back")
    }

    func testFirstLaunchOffersTheDemoAndLetsYouSkipIt() {
        relaunchAsFirstRun()
        XCTAssertTrue(app.buttons["onboardingLanguage"].waitForExistence(timeout: 10), "language choice on the first screen")
        let demo = app.buttons["onboardingDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "Try a demo")
        demo.tap()
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10), "tutorial opens")
        app.buttons["tutorialSkip"].tap()
        // skipping part-way still leads on to the permission page, never back into a loop
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5), "permission page after the tutorial")

        relaunchAsFirstRun()
        let skip = app.buttons["onboardingSkipDemo"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "Skip for now")
        skip.tap()
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5), "permission page")
        notNow.tap()
        XCTAssertTrue(notNow.waitForNonExistence(timeout: 5), "welcome closes")
        waitForNavigationTitle("Today")
        app.buttons["Settings"].tap()
        waitForNavigationTitle("Settings")   // normal use is not blocked
    }

    // MARK: helpers

    private var sampleStop: XCUIElement { app.descendants(matching: .any).matching(identifier: "tutorialStop").firstMatch }

    private func openTutorialFromSettings() {
        waitForNavigationTitle("Today")
        app.buttons["Settings"].tap()
        waitForNavigationTitle("Settings")
        app.buttons["replayTutorial"].tap()
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10), "tutorial opens on the sample day")
    }

    private func next() { app.buttons["tutorialNext"].tap() }

    /// A choice pill in Pip's card (the first match: the sample trip row offers the same modes further down).
    private func chip(_ label: String) -> XCUIElement {
        let chip = app.buttons[label].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "choice \(label)")
        return chip
    }

    private func row(containing s: String) -> XCUIElement { element(labelContaining: s) }

    private func relaunchAsFirstRun() {
        app.terminate()
        if let i = app.launchArguments.firstIndex(of: "-onboarded") { app.launchArguments[i + 1] = "NO" }
        app.launch()
    }
}
