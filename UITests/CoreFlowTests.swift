import XCTest

/// Baseline flows (issue #64): every tab, trip and visit details, map layers, Settings › Export.
/// They also check that the controls VoiceOver users depend on are reachable by their labels.
final class CoreFlowTests: HHTUITestCase {
    func testEveryTabOpens() {
        waitForNavigationTitle("Today")
        for (tab, title) in [("Timeline", "Timeline"), ("Map", "Map"), ("Stats", "Stats"), ("Places", "Places"), ("Today", "Today")] {
            openTab(tab)
            waitForNavigationTitle(title)
            XCTAssertTrue(app.buttons["tab-\(tab)"].isSelected, "\(tab) tab is announced as selected")
        }
    }

    func testTripDetailOpensAndCloses() {
        showYesterday()
        reveal(tripRows.firstMatch)
        tripRows.firstMatch.tap()
        waitForNavigationTitle("Trip")
        dismissSheet()
        XCTAssertTrue(tripRows.firstMatch.waitForExistence(timeout: 5))
    }

    func testVisitDetailOpensAndCloses() {
        showYesterday()
        reveal(visitRows.firstMatch)
        visitRows.firstMatch.tap()
        waitForNavigationTitle("Visit")
        dismissSheet()
        XCTAssertTrue(visitRows.firstMatch.waitForExistence(timeout: 5))
    }

    func testDayNavigationButtonsAreLabelled() {
        waitForNavigationTitle("Today")
        for label in ["Settings", "Previous day", "Choose day", "Next day"] {
            XCTAssertTrue(app.buttons[label].exists, "\(label) button")
        }
        XCTAssertFalse(app.buttons["Next day"].isEnabled, "can't go past today")
    }

    func testMapLayersMenu() {
        openTab("Map")
        waitForNavigationTitle("Map")
        app.buttons["Map layers"].tap()
        XCTAssertTrue(app.switches["Routes"].waitForExistence(timeout: 5) || app.buttons["Routes"].exists)
    }

    func testSettingsExport() {
        waitForNavigationTitle("Today")
        app.buttons["Settings"].tap()
        waitForNavigationTitle("Settings")
        let export = app.buttons["Create export"]
        reveal(export)
        export.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Share '")).firstMatch.waitForExistence(timeout: 30),
                      "export finished and offers to share")
        dismissSheet()
    }
}
