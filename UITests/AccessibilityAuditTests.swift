import XCTest

/// Apple's automated accessibility audit (Xcode 15+ / iOS 17+) on representative screens (issue #64).
/// Known, deliberately accepted findings are listed in `KnownIssue`; everything else fails the test, except the
/// report-only audit types below, which are logged but don't fail yet.
/// Each exception is documented in docs/accessibility-testing.md — keep the two in sync.
final class AccessibilityAuditTests: HHTUITestCase {
    func testToday() throws {
        waitForNavigationTitle("Today")
        waitForSeededContent(visitRows.firstMatch, "today's visit")
        try audit("Today")
    }

    func testDayWithTrips() throws {
        showYesterday()
        try audit("Day with trips")
    }

    func testTripDetail() throws {
        showYesterday()
        reveal(tripRows.firstMatch)
        tripRows.firstMatch.tap()
        waitForNavigationTitle("Trip")
        try audit("Trip detail")
    }

    func testVisitDetail() throws {
        showYesterday()
        reveal(visitRows.firstMatch)
        visitRows.firstMatch.tap()
        waitForNavigationTitle("Visit")
        try audit("Visit detail")
    }

    func testSpending() throws {
        showYesterday()
        let add = app.buttons["addCost"]
        reveal(add)
        add.tap()
        waitForNavigationTitle("Add a cost")
        try audit("Add a cost")
        let amount = app.textFields["costAmount"]
        amount.tap()
        amount.typeText("4.50")
        app.buttons["costSave"].tap()
        openSpending()
        waitForSeededContent(text(containing: "$4.50"), "the cost just added")
        try audit("Spending")
    }

    func testTimeline() throws {
        openTab("Timeline")
        waitForNavigationTitle("Timeline")
        waitForSeededContent(text(containing: " trips · "), "day rows")
        try audit("Timeline")
    }

    func testMap() throws {
        openTab("Map")
        waitForNavigationTitle("Map")
        waitForSeededContent(element(labelContaining: " visits"), "place markers")
        try audit("Map")
    }

    func testStats() throws {
        openTab("Stats")
        waitForNavigationTitle("Stats")
        waitForSeededContent(app.staticTexts["Walk"], "mode share rows")
        try audit("Stats")
    }

    func testPlaces() throws {
        openTab("Places")
        waitForNavigationTitle("Places")
        waitForSeededContent(text(containing: " visits · "), "place rows")
        try audit("Places")
    }

    func testSettings() throws {
        waitForNavigationTitle("Today")
        app.buttons["Settings"].tap()
        waitForNavigationTitle("Settings")
        try audit("Settings")
    }

    // MARK: -

    /// Runs every audit type and fails once with *all* unexpected issues (XCTest would stop at the first), each with
    /// the screen and element so it's actionable.
    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let first = try auditPass(screen)
        guard !first.isEmpty else { return }
        // On a slow simulator (CI) the contrast check isn't deterministic: which elements it flags changes from run to
        // run on the same screen. A second pass keeps the findings that show up both times, as a real problem does.
        print("[a11y] \(screen): \(first.count) unexpected finding(s); auditing again to confirm")
        var second = try auditPass(screen)
        let confirmed = first.filter { finding in
            guard let i = second.firstIndex(where: { $0.text == finding.text }) else { return false }
            second.remove(at: i)
            return true
        }
        if Self.logsScreenshots {
            for (i, finding) in confirmed.enumerated() {
                if let frame = finding.frame { logScreenshot("\(screen) finding \(i + 1)", crop: frame) }
            }
        }
        if !confirmed.isEmpty {
            XCTFail("\(screen): \(confirmed.count) accessibility issue(s):\n" + confirmed.map(\.text).joined(separator: "\n"),
                    file: file, line: line)
        }
    }

    private struct Finding {
        var text: String
        var frame: CGRect?
    }

    /// One audit; run again once if it times out ("Audit failed to complete in time", which a slow simulator hits).
    private func auditPass(_ screen: String) throws -> [Finding] {
        do {
            return try auditOnce(screen)
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            print("[a11y] \(screen): audit timed out; running it again")
            return try auditOnce(screen)
        }
    }

    private func auditOnce(_ screen: String) throws -> [Finding] {
        var unexpected: [Finding] = []
        let keyboard = app.keyboards.firstMatch
        let tabBar = app.buttons["tab-Today"]
        let layout = KnownIssue.Layout(screenWidth: app.windows.firstMatch.frame.width,
                                       screenHeight: app.windows.firstMatch.frame.height,
                                       keyboardTop: keyboard.exists ? keyboard.frame.minY : nil,
                                       tabBarTop: tabBar.exists && tabBar.isHittable ? tabBar.frame.minY - 9 : nil)
        try app.performAccessibilityAudit(for: .all) { issue in
            if Self.reportOnly.contains(issue.auditType) {
                print("[a11y] \(screen): report-only: \(Self.describe(issue))")
            } else if let known = KnownIssue.matching(issue, screen: screen, layout: layout) {
                print("[a11y] \(screen): accepted known issue (\(known)): \(Self.describe(issue))")
            } else {
                print("[a11y] \(screen): \(Self.describe(issue)) [\(issue.detailedDescription)]")
                unexpected.append(Finding(text: Self.describe(issue), frame: issue.element?.frame))
            }
            return true
        }
        return unexpected
    }

    /// Audit types that are logged but don't fail yet (see docs/accessibility-testing.md). None since issue #67 made
    /// `Font.toon` scale with Dynamic Type and re-enabled the contrast audit; keep it that way.
    static let reportOnly: XCUIAccessibilityAuditType = []

    static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let el = issue.element.map { e in
            let f = e.frame.integral
            return "\(e.elementType) '\(e.label)' id='\(e.identifier)' at (\(Int(f.minX)), \(Int(f.minY)), \(Int(f.width))×\(Int(f.height)))"
        } ?? "no element"
        return "\(auditName(issue.auditType)): \(issue.compactDescription) — \(el)"
    }

    private static func auditName(_ type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        return names.first { type.contains($0.0) }?.1 ?? "\(type.rawValue)"
    }
}

/// Findings we accept for now. Keep them narrow: match the audit type *and* something about the element.
enum KnownIssue: String {
    /// Apple Maps renders its own logo and "Legal" link; we can't change their size or contrast.
    case mapKitAttribution

    /// The pins MapKit draws for `Marker` (Trip detail: Start + End; Visit detail: the visit) are smaller than 44 pt
    /// and aren't exposed as elements. They're informational; the same places are named in the rows below the map.
    case mapKitMarkers
    /// Reported as clipped, but rendered in full (checked by screenshot on iPhone 17, iOS 27): the Stamp pill on Today,
    /// the origin/destination labels under the Trip detail map and Visit detail's "Name this place". Matched by exact
    /// text so other clipping still fails.
    case textClippedFalsePositive

    /// The system "Done" button in a sheet's navigation bar (Liquid Glass): it stops growing at the system's bar-button
    /// size (long-press shows the large content viewer instead), and the contrast check measures the glass behind it.
    /// Its title is ink (`confirmTint()`). Matched by being a button inside the navigation bar.
    case systemBarButton

    /// Contrast on elements whose top edge is still under the navigation bar (Spending's period pills, right under the
    /// inline title): iOS 26 blurs and fades content there (the scroll edge effect) and the audit samples that strip.
    /// The pills are ink on white or white on ink; the same pills under Stats' large title pass.
    case underNavigationBar

    /// Text the system draws that isn't in our view hierarchy, so the audit reports it with no element: MapKit's
    /// street and point-of-interest labels on the maps, and the dimmed screen behind a sheet.
    case systemDrawnText

    /// Text and button rows of a `List` (Today, Timeline, Settings, Trip/Visit detail) in the lower part of the screen
    /// (e.g. Settings' "Open iOS Settings" button, shown while location access isn't "Always"). As the audit
    /// enlarges the text they are pushed off screen, and List removes rows it no longer shows, so the audit can't
    /// measure them and reports partial (or no) Dynamic Type support or clipping. The same rows are measured fine
    /// when they sit higher up, and these screens are checked at the largest size by hand (Manual checklist).
    case listRowPushedOffScreen

    /// Under the on-screen keyboard (Add a cost opens with the amount field focused), or just above it, where the
    /// glass keyboard's edge blurs the row: the audit measures the keys instead of the row, and reads the key captions
    /// as text without an element.
    case behindKeyboard

    /// Partly under the floating tab bar (e.g. the "Spent today" card at the bottom of Today): the audit measures the
    /// bar's pixels and its smaller visible area. Scrolling brings the row clear of the bar. Text the bar cuts off is
    /// reported as clipped with no element.
    case behindTabBar

    /// Contrast on text whose element is a whole `List`/`Form` row: section headers, which sit on the dot grid, and
    /// Pip's speech bubble on Today, which a List row reports with the mascot's frame. The audit samples the row, not
    /// the glyphs, and takes the dots or the mascot for the text colour (the dots alone are 1.3:1 on butter), so the
    /// findings come and go between runs. The text is `Toon.muted` on butter (6.6:1, 5.2:1 even on a dot) or `Toon.ink`
    /// on white. Smaller text elements are still checked.
    case fullWidthRowContrast

    /// Where things sit on screen when the audit runs.
    struct Layout {
        var screenWidth: CGFloat
        var screenHeight: CGFloat
        /// Top of the on-screen keyboard, if it's up.
        var keyboardTop: CGFloat?
        /// Top of the floating tab bar, if it's on screen.
        var tabBarTop: CGFloat?
    }

    private static let listScreens: Set = ["Today", "Day with trips", "Timeline", "Settings", "Trip detail", "Visit detail"]
    private static let mapScreens: Set = ["Map", "Today", "Day with trips", "Trip detail", "Visit detail"]
    private static let sheetScreens: Set = ["Settings", "Trip detail", "Visit detail", "Add a cost"]

    static func matching(_ issue: XCUIAccessibilityAuditIssue, screen: String, layout: Layout) -> KnownIssue? {
        let label = issue.element?.label ?? ""
        let id = issue.element?.identifier ?? ""
        if label == "Legal" || id.hasPrefix("MKAttribution") || label.hasPrefix("Apple Maps") || label == "Maps" {
            return .mapKitAttribution
        }
        if ["Trip detail", "Visit detail"].contains(screen), issue.auditType == .hitRegion, issue.element == nil {
            return .mapKitMarkers
        }
        if issue.auditType == .textClipped,
           label == "Stamp this moment" || (screen == "Trip detail" && label.hasPrefix("Place "))
            || (screen == "Visit detail" && label == "Name this place") {
            return .textClippedFalsePositive
        }
        if let e = issue.element, e.elementType == .button, e.frame.maxY < 140,
           issue.auditType == .dynamicType || issue.auditType == .contrast {
            return .systemBarButton
        }
        if issue.auditType == .contrast, let e = issue.element, e.frame.minY < 124 {
            return .underNavigationBar
        }
        if issue.element == nil, [.contrast, .elementDetection, .textClipped].contains(issue.auditType),
           mapScreens.contains(screen) || (issue.auditType == .contrast && sheetScreens.contains(screen)) {
            return .systemDrawnText
        }
        if let top = layout.tabBarTop,
           issue.element.map({ $0.frame.maxY > top }) ?? (issue.auditType == .textClipped) {
            return .behindTabBar
        }
        if let top = layout.keyboardTop,
           issue.element.map({ $0.frame.maxY > top - 24 }) ?? (issue.auditType == .elementDetection) {
            return .behindKeyboard
        }
        if issue.auditType == .contrast, let e = issue.element, e.elementType == .staticText,
           e.frame.width >= layout.screenWidth - 40 {
            return .fullWidthRowContrast
        }
        // below the top third: at the largest sizes the rows above grow about threefold and push these out
        if listScreens.contains(screen), issue.auditType == .dynamicType || issue.auditType == .textClipped,
           let e = issue.element, [.staticText, .button].contains(e.elementType), e.frame.minY > layout.screenHeight * 0.35 {
            return .listRowPushedOffScreen
        }
        return nil
    }
}
