import XCTest

/// Costs (issue #17): Today's prompt, adding a cost from a trip, the day card, and the Spending page.
final class CostFlowTests: HHTUITestCase {
    func testAddCostFromTripShowsOnTodayAndInSpending() {
        showYesterday()
        reveal(tripRows.firstMatch)
        tripRows.firstMatch.tap()
        waitForNavigationTitle("Trip")
        let add = app.buttons["detailAddCost"]
        reveal(add)
        add.tap()
        enterCost("2.90")
        dismissSheet()

        // the trip row carries the cost, and the day card adds it up
        XCTAssertTrue(element(labelContaining: "Cost $2.90").waitForExistence(timeout: 5), "cost badge on the trip row")
        let card = app.descendants(matching: .any).matching(identifier: "daySpend").firstMatch
        reveal(card)
        XCTAssertTrue(text(containing: "$2.90").exists, "Spent this day total")

        openSpending()
        XCTAssertTrue(text(containing: "$2.90 over 1 day").waitForExistence(timeout: 5), "spending summary")
        XCTAssertTrue(app.staticTexts["Every cost"].exists || text(containing: "Every cost").exists)
    }

    func testDayCardAddsAnUnlinkedCost() {
        showYesterday()
        let add = app.buttons["addCost"]
        reveal(add)
        add.tap()
        enterCost("12")
        // an unlinked cost is its own row in the timeline, usually below the fold
        waitForSeededContent(app.descendants(matching: .any).matching(identifier: "costRow").firstMatch,
                             "the new cost in the day", firstWait: 3)
    }

    func testPromptOffersFreeForAPaidTrip() throws {
        showYesterday()
        // one card per unpaid trip or stay (issue #75): answering one leaves the others
        let prompts = app.descendants(matching: .any).matching(identifier: "costPrompt")
        let trip = prompts.containing(.button, identifier: "Free").firstMatch
        guard trip.waitForExistence(timeout: 5) else { throw XCTSkip("no transit trip in yesterday's demo data") }
        let before = prompts.count
        trip.buttons["Free"].tap()
        waitForSeededContent(element(labelContaining: "Cost Free"), "free badge on the trip", firstWait: 3)
        XCTAssertEqual(prompts.count, before - 1, "only the answered prompt goes away")
    }

    private func enterCost(_ amount: String) {
        waitForNavigationTitle("Add a cost")
        let field = app.textFields["costAmount"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !field.hasFocus { field.tap() }
        // the sheet focuses the field itself; keys typed before the keyboard is up are lost
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard")
        field.typeText(amount)
        app.buttons["costSave"].tap()
        XCTAssertFalse(app.navigationBars["Add a cost"].waitForExistence(timeout: 2), "sheet closes on save")
    }
}

private extension XCUIElement {
    var hasFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}
