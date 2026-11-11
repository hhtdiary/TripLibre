import Foundation

/// On-device recall of the user's own saved places near a detected stop (issue #95).
///
/// GPS can tell that the user stopped, but not which of several places at nearly the same coordinates (two floors of
/// one building, neighbouring shops) they were at. Instead of guessing, the app lists the places the user has marked
/// before, nearest first, and lets them pick one, decline them all, or skip. This type only ranks; it never assigns a
/// place, and it reads nothing but the places passed in (no POI service, no network).
public enum PlaceRecall {
    /// Default search radius around the stop, in meters.
    public static let defaultRadius: Double = 150
    /// Radii offered in Settings.
    public static let radiusChoices: [Double] = [50, 100, 150, 250, 500]
    /// At most this many candidates are listed.
    public static let defaultLimit = 8
    /// Distances closer than this (m) are treated as equal, so the place used more often (then more recently) comes
    /// first. GPS cannot order places this close anyway.
    public static let tieTolerance: Double = 20

    public struct Candidate: Identifiable, Equatable, Sendable {
        public var place: Place
        /// Distance from the detected stop to the saved place's center.
        public var distance: Double
        public var visitCount: Int
        public var lastVisit: Date?
        public var id: String { place.id }

        public init(place: Place, distance: Double, visitCount: Int = 0, lastVisit: Date? = nil) {
            self.place = place; self.distance = distance; self.visitCount = visitCount; self.lastVisit = lastVisit
        }
    }

    /// A place the user marked themselves: named, given a type, floor/unit or notes, made a favorite, created by
    /// hand, or chosen for at least one visit. Places inference created and nobody touched are not recalled.
    public static func isUserMarked(_ p: Place, confirmedPlaceIDs: Set<String>) -> Bool {
        guard !p.deleted, p.mergedInto == nil else { return false }
        return p.isNamed || p.category != nil || Place.cleanCustom(p.unit) != nil || Place.cleanCustom(p.notes) != nil
            || p.favorite || p.source == .manual || confirmedPlaceIDs.contains(p.id)
    }

    /// The user-marked places within `radius` m of `stop`, nearest first; near-ties go to the more visited, then
    /// more recently visited place. Places at identical coordinates stay separate candidates.
    public static func candidates(near stop: Coordinate, places: [Place], stats: [String: TravelStore.PlaceStats] = [:],
                                  confirmedPlaceIDs: Set<String> = [], radius: Double = defaultRadius,
                                  limit: Int = defaultLimit) -> [Candidate] {
        let found = places
            .filter { isUserMarked($0, confirmedPlaceIDs: confirmedPlaceIDs) }
            .map { p in
                Candidate(place: p, distance: Geo.distance(p.coordinate, stop), visitCount: stats[p.id]?.visitCount ?? 0,
                          lastVisit: stats[p.id]?.lastVisit)
            }
            .filter { $0.distance <= radius }
        let sorted = found.sorted { a, b in
            let ba = Int(a.distance / tieTolerance), bb = Int(b.distance / tieTolerance)
            if ba != bb { return ba < bb }
            if a.visitCount != b.visitCount { return a.visitCount > b.visitCount }
            let la = a.lastVisit ?? .distantPast, lb = b.lastVisit ?? .distantPast
            if la != lb { return la > lb }
            if a.distance != b.distance { return a.distance < b.distance }
            return a.place.id < b.place.id   // deterministic
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    // MARK: - Today's place review (issue #116)

    /// Another saved place within this many meters of the matched one's distance makes the match a guess.
    public static let ambiguityMargin: Double = 40
    /// A home or work place matched at least this often is recognised, not guessed, even with a neighbour close by.
    public static let habitualVisits = 3

    /// Whether Today should ask the user which place a visit was. `candidates` are the visit's recall candidates.
    ///
    /// Asks only while the place is still the automatic match, and only when the user's saved places leave real doubt:
    /// a saved place is near but the stop was matched to some other (unsaved) place, or a second saved place is about
    /// as close as the matched one. A lone nearby saved place, and a home or work place recognised again and again, are
    /// high-confidence matches and never asked about. A finished stop only: an ongoing one may still move.
    public static func needsReview(_ v: Visit, candidates: [Candidate]) -> Bool {
        guard !v.deleted, v.placeStatus == .auto, v.departure != nil, !candidates.isEmpty else { return false }
        guard let current = candidates.first(where: { $0.id == v.placeID }) else { return true }
        if current.place.category == .home || current.place.category == .workSchool, current.visitCount >= habitualVisits {
            return false
        }
        return candidates.contains { $0.id != current.id && $0.distance <= current.distance + ambiguityMargin }
    }
}
