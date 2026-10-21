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
        XCTAssertTrue(tripRows.firstMatch.waitForExistence(timeout: 60), "demo inference produced no trips")
    }

    var tripRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "tripRow") }
    var visitRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "visitRow") }

    /// Scrolls until `element` sits fully above the floating tab bar (or the bottom of a sheet). XCUITest's own
    /// "scroll to visible" stops as soon as the element's centre is on screen, where the tab bar would take the tap.
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        let tabBar = app.buttons["tab-Today"]
        let limit = (tabBar.exists && tabBar.isHittable ? tabBar.frame.minY - 12 : window.frame.maxY) - 24
        // drag in the left margin: the middle of the day screen is a map, which would pan instead of scrolling
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: limit - 20))
        for _ in 0..<10 where !element.exists || element.frame.maxY > limit {
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)))
        }
        XCTAssertTrue(element.exists && element.frame.maxY <= limit, "couldn't scroll \(element) into view", file: file, line: line)
    }

    func dismissSheet(_ button: String = "Done") {
        let done = app.navigationBars.buttons[button].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "\(button) button")
        done.tap()
    }

    func waitForNavigationTitle(_ title: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: timeout), "screen \(title)")
    }
}
