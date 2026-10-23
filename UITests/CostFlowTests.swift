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

        card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        waitForNavigationTitle("Spending")
        XCTAssertTrue(text(containing: "$2.90 over 1 day").waitForExistence(timeout: 5), "spending summary")
        XCTAssertTrue(app.staticTexts["Every cost"].exists || text(containing: "Every cost").exists)
    }

    func testDayCardAddsAnUnlinkedCost() {
        showYesterday()
        let add = app.buttons["addCost"]
        reveal(add)
        add.tap()
        enterCost("12")
        XCTAssertTrue(element(labelContaining: "Cost $12.00").waitForExistence(timeout: 5)
            || app.descendants(matching: .any).matching(identifier: "costRow").firstMatch.waitForExistence(timeout: 5),
            "the new cost shows in the day")
    }

    func testPromptOffersFreeForAPaidTrip() throws {
        showYesterday()
        let prompt = app.descendants(matching: .any).matching(identifier: "costPrompt").firstMatch
        guard prompt.waitForExistence(timeout: 5) else { throw XCTSkip("no transit trip in yesterday's demo data") }
        prompt.buttons["Free"].tap()
        XCTAssertTrue(element(labelContaining: "Cost Free").waitForExistence(timeout: 5), "free badge on the trip")
        XCTAssertFalse(prompt.exists, "the prompt moves on once answered")
    }

    private func enterCost(_ amount: String) {
        waitForNavigationTitle("Add a cost")
        let field = app.textFields["costAmount"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !field.hasFocus { field.tap() }
        field.typeText(amount)
        app.buttons["costSave"].tap()
        XCTAssertFalse(app.navigationBars["Add a cost"].waitForExistence(timeout: 2), "sheet closes on save")
    }
}

private extension XCUIElement {
    var hasFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}
