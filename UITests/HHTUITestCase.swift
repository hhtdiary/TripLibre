import UIKit
import XCTest

/// Launches the app on a fresh demo database (`-hhtUITest`, see AppModel.isUITest): three days of synthetic
/// Philadelphia travel, onboarding skipped, no location collection. Yesterday always has trips and visits.
class HHTUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hhtUITest", "YES", "-onboarded", "YES", "-hhtTab", "0",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    // MARK: navigation

    func openTab(_ title: String) {
        let tab = app.buttons["tab-\(title)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(title)")
        tab.tap()
    }

    /// Today → yesterday, waiting until inference has turned the demo points into diary rows.
    func showYesterday() {
        let previous = app.buttons["Previous day"]
        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        previous.tap()
        waitForSeededContent(tripRows.firstMatch, "yesterday's trips")
    }

    /// Screens show their title at once but fill in only after the launch-time inference run turns the demo points
    /// into trips, visits and places. Wait for something that only exists afterwards, so audits see populated screens.
    /// If it's still missing once inference has had time, scroll down to look for it (on the day screen the rows sit
    /// below the cost prompt, banner and map, and a List only builds the rows near the screen), then back to the top,
    /// so the audit and the next step start there.
    func waitForSeededContent(_ element: XCUIElement, _ what: String, firstWait: TimeInterval = 20,
                              file: StaticString = #filePath, line: UInt = #line) {
        var found = element.waitForExistence(timeout: firstWait)
        var scrolled = 0
        while !found && scrolled < 12 {
            scrollDown()
            scrolled += 1
            found = element.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(found, "\(what) never appeared; demo inference unfinished?", file: file, line: line)
        for _ in 0..<scrolled { scrollUp() }
    }

    func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func element(labelContaining s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    var tripRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "tripRow") }
    var visitRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "visitRow") }

    /// Scrolls until `element` sits fully above the floating tab bar (or the bottom of a sheet). XCUITest's own
    /// "scroll to visible" stops as soon as the element's centre is on screen, where the tab bar would take the tap.
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let limit = visibleBottom
        for _ in 0..<10 where !element.exists || element.frame.maxY > limit {
            scrollDown()
        }
        XCTAssertTrue(element.exists && element.frame.maxY <= limit, "couldn't scroll \(element) into view", file: file, line: line)
    }

    /// Bottom of the area not covered by the floating tab bar (or of a sheet). Not `isHittable`: right after a sheet
    /// closes the bar can read as not hittable, and `reveal` then left rows under it, where a tap hits a tab.
    private var visibleBottom: CGFloat {
        let tabBar = app.buttons["tab-Today"]
        return (tabBar.exists ? tabBar.frame.minY - 12 : app.windows.firstMatch.frame.maxY) - 24
    }

    /// Drags the content up by 250 pt, in the left margin: the middle of the day screen is a map, which would pan
    /// instead of scrolling. Holding at the end stops it there, so it doesn't fling on under the next tap.
    private func scrollDown() {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: visibleBottom - 20))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)), withVelocity: .slow,
                    thenHoldForDuration: 0.2)
    }

    private func scrollUp() {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: visibleBottom - 270))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 250)), withVelocity: .slow,
                    thenHoldForDuration: 0.2)
    }

    /// Taps the day's spend card and waits for Spending. Right after a cost is saved the day list can reload and jump
    /// back to the top between `reveal` and the tap, which then lands on the tab bar; so reveal and tap again.
    func openSpending(file: StaticString = #filePath, line: UInt = #line) {
        let card = app.descendants(matching: .any).matching(identifier: "daySpend").firstMatch
        let spending = app.navigationBars["Spending"]
        for attempt in 1...3 {
            reveal(card)
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            if spending.waitForExistence(timeout: 5) { return }
            if Self.logsScreenshots { logScreenshot("tap \(attempt) on the spend card didn't open Spending") }
        }
        XCTFail("screen Spending", file: file, line: line)
    }

    func dismissSheet(_ button: String = "Done") {
        let done = app.navigationBars.buttons[button].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "\(button) button")
        done.tap()
        // until the sheet has gone, the screen under it (and its tab bar) isn't in the accessibility tree, and reveal()
        // would measure against the window's bottom and leave rows under the tab bar
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "sheet closes")
    }

    func waitForNavigationTitle(_ title: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: timeout), "screen \(title)")
    }

    // MARK: screenshots in the log

    /// CI sets `TEST_RUNNER_HHT_LOG_SCREENSHOTS=1` (xcodebuild hands it to the tests without the prefix): each failure
    /// then also prints a screenshot to the log, base64-encoded, for when the .xcresult bundle isn't at hand.
    static let logsScreenshots = ProcessInfo.processInfo.environment["HHT_LOG_SCREENSHOTS"] == "1"

    override func record(_ issue: XCTIssue) {
        if Self.logsScreenshots { logScreenshot("failure") }
        super.record(issue)
    }

    /// Prints the screen (at 1x, JPEG) or, given a frame in points, that part of it (at 2x, PNG, so colours are exact)
    /// as one `[screenshot <name>] <base64>` line.
    func logScreenshot(_ name: String, crop: CGRect? = nil) {
        let shot = XCUIScreen.main.screenshot().image
        let bounds = CGRect(origin: .zero, size: shot.size)
        let rect = crop.map { $0.insetBy(dx: -8, dy: -8).intersection(bounds) } ?? bounds
        guard !rect.isEmpty else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = crop == nil ? 1 : 2
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            shot.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
        guard let data = crop == nil ? image.jpegData(compressionQuality: 0.6) : image.pngData() else { return }
        print("[screenshot \(name)] \(data.base64EncodedString())")
    }
}
