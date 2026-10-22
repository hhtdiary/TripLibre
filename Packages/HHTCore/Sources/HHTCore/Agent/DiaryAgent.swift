import Foundation

/// What the diary agent knows how to do. Everything is deterministic and runs over the local store:
/// no language model and no network are involved, so the same diary always gets the same prompts and answers.
public enum DiaryAgent {

    // MARK: - Day summary

    /// One step of the day's trip chain: a stop, or the leg that joins two stops.
    public enum ChainStep: Equatable, Sendable {
        /// `visitID` is set when the stop is one the agent is asking about.
        case stop(label: String, askingVisitID: String?)
        case leg(TravelMode)
    }

    public struct DaySummary: Equatable, Sendable {
        public var trips: Int
        public var places: Int
        public var distance: Double
        public var chain: [ChainStep]
    }

    /// The day as a chain of stops and legs, in time order. `label` names a stop the user has not named
    /// (typically "? 14:12"), so the caller controls time formatting.
    public static func summarize(visits: [Visit], trips: [Trip], places: [String: Place], asking: Set<String>,
                                 label: (Visit) -> String) -> DaySummary {
        let vs = visits.filter { !$0.deleted }, ts = trips.filter { !$0.deleted }
        let events: [(Date, ChainStep)] = vs.map { v in
            let p = v.placeID.flatMap { places[$0] }
            let name = p?.isNamed == true ? p!.displayName : label(v)
            return (v.arrival, .stop(label: name, askingVisitID: asking.contains(v.id) ? v.id : nil))
        } + ts.map { ($0.departure, .leg($0.mode)) }
        let placeKeys = Set(vs.map { $0.placeID ?? "visit-" + $0.id })
        return DaySummary(trips: ts.count, places: placeKeys.count, distance: ts.map(\.distance).reduce(0, +),
                          chain: events.sorted { $0.0 < $1.0 }.map(\.1))
    }

    // MARK: - Prompted recall

    /// Purposes offered as one-tap answers, most common first.
    public static let recallChoices: [TripPurpose] = [.meal, .shopping, .personalBusiness, .social, .escort, .other]

    /// Finished stops worth asking about: untouched by the user, no purpose yet, at an unnamed place,
    /// long enough to have been an activity rather than a pause in traffic, and short enough not to be
    /// an overnight stay (which is home, a hotel or a friend's, not an errand).
    public static func recallCandidates(visits: [Visit], places: [String: Place], now: Date = Date(),
                                        minDwell: TimeInterval = 10 * 60, maxDwell: TimeInterval = 8 * 3600) -> [Visit] {
        visits.filter { v in
            !v.deleted && v.userStatus == .auto && v.purpose == nil && v.departure != nil
                && (minDwell...maxDwell).contains(v.duration(now: now))
                && !(v.placeID.flatMap { places[$0] }?.isNamed ?? false)
        }
        .sorted { $0.arrival < $1.arrival }
    }

    // MARK: - Mode corrections

    public enum Reason: Equatable, Sendable {
        /// The user chose `mode` on `count` of their last `of` corrected trips between the same two places.
        case habit(mode: TravelMode, count: Int, of: Int)
        /// Mean speed over the whole trip, m/s.
        case averageSpeed(Double)
        /// The classifier's own confidence, 0–1 (nil when it gave none).
        case lowConfidence(Double?)
    }

    public struct ModeProposal: Equatable, Sendable {
        public var tripID: String
        public var current: TravelMode
        /// nil: the agent has no better guess and asks the user to pick.
        public var proposed: TravelMode?
        public var reasons: [Reason]
    }

    /// A correction worth raising for an untouched trip, or nil when the automatic mode looks right.
    /// `history` is the user's past mode choices between the same two places, most recent first
    /// (`TravelStore.correctedModes`).
    public static func modeProposal(for trip: Trip, history: [TravelMode]) -> ModeProposal? {
        guard !trip.deleted, trip.userStatus == .auto else { return nil }
        let speed = trip.duration > 0 ? trip.distance / trip.duration : nil
        if let (mode, count) = habit(history), mode != trip.mode {
            var reasons: [Reason] = [.habit(mode: mode, count: count, of: history.count)]
            if let speed { reasons.append(.averageSpeed(speed)) }
            if trip.needsReview { reasons.append(.lowConfidence(trip.modeConfidence)) }
            return ModeProposal(tripID: trip.id, current: trip.mode, proposed: mode, reasons: reasons)
        }
        guard trip.needsReview else { return nil }
        var reasons: [Reason] = [.lowConfidence(trip.modeConfidence)]
        if let speed { reasons.append(.averageSpeed(speed)) }
        return ModeProposal(tripID: trip.id, current: trip.mode, proposed: nil, reasons: reasons)
    }

    /// The mode chosen on a clear majority (≥ 2 trips and ≥ 60 %) of past corrections; ties go to the most recent.
    static func habit(_ history: [TravelMode]) -> (TravelMode, Int)? {
        guard !history.isEmpty else { return nil }
        var counts: [TravelMode: Int] = [:]
        for m in history { counts[m, default: 0] += 1 }
        let best = counts.values.max()!
        guard let mode = history.first(where: { counts[$0] == best }),
              best >= 2, Double(best) / Double(history.count) >= 0.6 else { return nil }
        return (mode, best)
    }

    // MARK: - Questions

    public enum Topic: String, CaseIterable, Sendable {
        case modeShare, distance, trips, places
    }

    /// The topic a free-text question is about, by keyword; nil when none matches.
    /// Checked in order, so "how far did I bike" is about distance rather than modes.
    public static func topic(for question: String) -> Topic? {
        let q = question.lowercased()
        let keywords: [(Topic, [String])] = [
            (.distance, ["how far", "distance", "km", "mile"]),
            (.places, ["where", "place", "most time", "spend"]),
            (.trips, ["how many", "how often", "trips", "busy"]),
            (.modeShare, ["mode", "commute", "bike", "cycl", "walk", "transit", "bus", "subway", "train", "car", "drive",
                          "get around"]),
        ]
        return keywords.first { $0.1.contains(where: q.contains) }?.0
    }

    public struct Answer: Equatable, Sendable {
        public var topic: Topic
        public var days: Int
        /// The last `days` days, ending today.
        public var current: MobilityMetrics
        /// The `days` days before that, for comparison.
        public var previous: MobilityMetrics
    }

    public static func answer(_ topic: Topic, store: TravelStore, now: Date = Date(), days: Int = 30,
                              calendar: Calendar = .current) throws -> Answer {
        let cur = DateRange.lastDays(days, until: now, calendar: calendar)
        let prev = DateRange.lastDays(days, until: calendar.date(byAdding: .day, value: -days, to: now)!, calendar: calendar)
        return Answer(topic: topic, days: days,
                      current: try Analytics.compute(store: store, range: cur, now: now),
                      previous: try Analytics.compute(store: store, range: prev, now: now))
    }
}
