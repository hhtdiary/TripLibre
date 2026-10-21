import XCTest

/// Apple's automated accessibility audit (Xcode 15+ / iOS 17+) on representative screens (issue #64).
/// Known, deliberately accepted findings are listed in `KnownIssue`; everything else fails the test, except the
/// report-only audit types below, which are logged but don't fail yet.
/// Each exception is documented in docs/accessibility-testing.md — keep the two in sync.
final class AccessibilityAuditTests: HHTUITestCase {
    func testToday() throws {
        waitForNavigationTitle("Today")
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

    func testTimeline() throws {
        openTab("Timeline")
        waitForNavigationTitle("Timeline")
        try audit("Timeline")
    }

    func testMap() throws {
        openTab("Map")
        waitForNavigationTitle("Map")
        try audit("Map")
    }

    func testStats() throws {
        openTab("Stats")
        waitForNavigationTitle("Stats")
        try audit("Stats")
    }

    func testPlaces() throws {
        openTab("Places")
        waitForNavigationTitle("Places")
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
        var unexpected: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            if Self.reportOnly.contains(issue.auditType) {
                print("[a11y] \(screen): report-only: \(Self.describe(issue))")
            } else if let known = KnownIssue.matching(issue, screen: screen) {
                print("[a11y] \(screen): accepted known issue (\(known)): \(Self.describe(issue))")
            } else {
                print("[a11y] \(screen): \(Self.describe(issue))")
                unexpected.append(Self.describe(issue))
            }
            return true
        }
        if !unexpected.isEmpty {
            XCTFail("\(screen): \(unexpected.count) accessibility issue(s):\n" + unexpected.joined(separator: "\n"), file: file, line: line)
        }
    }

    /// Logged, not failing (see docs/accessibility-testing.md › Report-only audits):
    /// - dynamicType: `Font.toon` uses fixed point sizes app-wide; scaling them needs layout work on every sticker card.
    /// - contrast: flags ink-on-white text on the tilted, shadowed sticker cards (≥ 12:1 by the palette), so it's
    ///   mostly noise until those cards are restructured. Colour changes are checked against the palette instead.
    static let reportOnly: XCUIAccessibilityAuditType = [.dynamicType, .contrast]

    static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let el = issue.element.map { "\($0.elementType) '\($0.label)' id='\($0.identifier)'" } ?? "no element"
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

    /// MapKit draws annotation titles and street names itself; the audit sees text it can't attribute to an element.
    case mapKitLabels

    /// The pins MapKit draws for `Marker` (Trip detail: Start + End; Visit detail: the visit) are smaller than 44 pt
    /// and aren't exposed as elements. They're informational; the same places are named in the rows below the map.
    case mapKitMarkers
    /// Reported as clipped, but rendered in full (checked by screenshot on iPhone 17, iOS 27): the Stamp pill on Today
    /// and the origin/destination labels under the Trip detail map. Matched by exact text so other clipping still fails.
    case textClippedFalsePositive

    static func matching(_ issue: XCUIAccessibilityAuditIssue, screen: String) -> KnownIssue? {
        let label = issue.element?.label ?? ""
        let id = issue.element?.identifier ?? ""
        if label == "Legal" || id.hasPrefix("MKAttribution") || label.hasPrefix("Apple Maps") || label == "Maps" {
            return .mapKitAttribution
        }
        if screen == "Map", issue.auditType == .elementDetection, issue.element == nil {
            return .mapKitLabels
        }
        if ["Trip detail", "Visit detail"].contains(screen), issue.auditType == .hitRegion, issue.element == nil {
            return .mapKitMarkers
        }
        if issue.auditType == .textClipped,
           label == "Stamp this moment" || (screen == "Trip detail" && label.hasPrefix("Place ")) {
            return .textClippedFalsePositive
        }
        return nil
    }
}
