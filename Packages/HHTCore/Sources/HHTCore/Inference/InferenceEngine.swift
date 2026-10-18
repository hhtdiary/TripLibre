import Foundation

/// Turns raw observations into visits and trips, without ever overwriting user-corrected records.
///
/// Reprocessing contract (docs/inference.md §6):
/// * Records with `user_status != 'auto'` (and auto visits referenced by such trips) are *locked*.
/// * Locked records are never modified, except that an ongoing locked visit may receive a departure time.
/// * Detected stays/movements that overlap locked records are absorbed by them.
/// * Auto records inside the window are updated in place when they match a detection (stable IDs),
///   otherwise deleted and replaced.
public final class InferenceEngine {
    public let store: TravelStore
    public var config: InferenceConfig
    /// Optional hook to enrich newly created places (e.g. reverse geocoding, if the user enabled it).
    public var onPlaceCreated: ((Place) -> Void)?
    /// Optional hook called at each phase boundary (and every few stays while resolving), on the inference thread.
    public var onProgress: ((Progress) -> Void)?

    public init(store: TravelStore, config: InferenceConfig = .default) {
        self.store = store
        self.config = config
    }

    public struct Report: Equatable, Sendable {
        public var windowStart: Date
        public var windowEnd: Date
        public var pointsConsidered = 0
        public var visitsCreated = 0
        public var visitsUpdated = 0
        public var visitsRemoved = 0
        public var tripsCreated = 0
        public var tripsRemoved = 0
        public var placesCreated = 0
    }

    public enum Phase: String, Sendable {
        case loadingPoints, detectingStays, resolvingVisits, buildingTrips, finalizing
    }

    /// A snapshot of a run in flight: the phase, what has been done so far, and how many stays are resolved.
    public struct Progress: Equatable, Sendable {
        public var phase: Phase
        public var report: Report
        public var staysResolved = 0
        public var staysTotal = 0
    }

    /// Accurate points newer than the diary's last stop that no run has turned into a visit or trip yet.
    public struct UnresolvedTail: Equatable, Sendable {
        public var since: Date
        public var lastPoint: Date
        public var pointCount: Int
    }

    /// When the last run committed (nil if inference has never run).
    public var lastRunAt: Date? {
        store.meta("last_inference_at").flatMap { isoFormatter.date(from: $0) }
    }

    /// Raw data past the latest visit: points after it closed, or, while it is still open,
    /// from the first fix that left it. Nil when nothing (or only a couple of fixes) is outstanding.
    public func unresolvedTail(now: Date = Date()) throws -> UnresolvedTail? {
        let detector = StayDetector(config: config)
        let tail: [RawPoint]
        if let v = try store.latestVisit() {
            let pts = detector.clean(try store.points(from: v.departure ?? v.arrival, to: now))
            if v.departure != nil {
                tail = pts
            } else {
                let radius = max(try v.placeID.flatMap(store.place)?.radius ?? config.newPlaceRadius, config.stayRadius)
                    + config.placeMatchSlack
                guard let i = pts.firstIndex(where: { Geo.distance($0.coordinate, v.coordinate) > radius }) else { return nil }
                tail = Array(pts[i...])
            }
        } else if let first = store.firstPointDate() {
            tail = detector.clean(try store.points(from: first, to: now))
        } else {
            return nil
        }
        guard tail.count >= 3, let a = tail.first, let b = tail.last else { return nil }
        return UnresolvedTail(since: a.timestamp, lastPoint: b.timestamp, pointCount: tail.count)
    }

    /// Incremental run: reprocesses from the arrival of the latest visit (or the first point) to now.
    @discardableResult
    public func processNew(now: Date = Date()) throws -> Report {
        let start: Date
        if let latest = try store.latestVisit(includeDeleted: true) {
            start = latest.arrival
        } else if let first = store.firstPointDate() {
            start = first
        } else {
            return Report(windowStart: now, windowEnd: now)
        }
        return try process(from: start, to: now, now: now)
    }

    /// Reprocess a time range. The window is widened to whole visits at both ends.
    @discardableResult
    public func process(from requestedStart: Date, to requestedEnd: Date, now: Date = Date()) throws -> Report {
        // widen to visit boundaries so we never cut a stay in half
        var from = requestedStart, to = min(requestedEnd, now)
        if let v = try store.visits(overlapping: from, from, includeDeleted: true).first { from = min(from, v.arrival) }
        if let v = try store.visits(overlapping: to, to, includeDeleted: true).last {
            to = max(to, min(v.departure ?? now, now))
        }

        var report = Report(windowStart: from, windowEnd: to)
        func progress(_ phase: Phase, _ done: Int = 0, of total: Int = 0) {
            onProgress?(Progress(phase: phase, report: report, staysResolved: done, staysTotal: total))
        }
        progress(.loadingPoints)
        try store.db.transaction {
            // a little context before the window so the anchor stay is detected exactly as in a full run
            let points = try store.points(from: from.addingTimeInterval(-config.contextMargin), to: to)
            report.pointsConsidered = points.count
            progress(.detectingStays)
            let motion = MotionTimeline(try store.motion(from: from.addingTimeInterval(-3600), to: to))
            let detector = StayDetector(config: config)
            let clean = detector.clean(points)
            // stamps the user tapped add short stops the sensors alone would miss (§8)
            let anchoring = StampAnchoring(config: config)
            let stamps = try store.stamps(from: from.addingTimeInterval(-config.stampTimeTolerance), to: to)
            let stays = anchoring.anchor(stamps.filter { $0.timestamp >= from },
                                         stays: detector.mergeStays(detector.detect(points, motion: motion, now: now), points: clean),
                                         points: clean, now: now)
                .filter { ($0.end ?? now) > from }

            // existing records in the window
            let existingVisits = try store.visits(overlapping: from, to, includeDeleted: true)
                .filter { $0.arrival >= from && $0.arrival <= to }
            let existingTrips = try store.trips(overlapping: from, to, includeDeleted: true, withSegments: false)
                .filter { $0.departure >= from && $0.departure <= to }
            let lockedTrips = existingTrips.filter { $0.userStatus.isLocked }
            // a locked trip pins its endpoint visits even when it departs before the window
            // (e.g. a corrected trip into the visit the incremental run starts from)
            var lockedVisitIDs = Set(lockedTrips.flatMap { [$0.originVisitID, $0.destinationVisitID].compactMap { $0 } })
            for v in existingVisits where try store.tripsReferencing(visitID: v.id, includeDeleted: true)
                .contains(where: { $0.userStatus.isLocked }) {
                lockedVisitIDs.insert(v.id)
            }
            func isLocked(_ v: Visit) -> Bool { v.userStatus.isLocked || lockedVisitIDs.contains(v.id) }
            var lockedVisits = existingVisits.filter(isLocked)
            var reusableAuto = existingVisits.filter { !isLocked($0) && !$0.deleted }
            var keptVisitIDs = Set<String>()

            func overlap(_ a0: Date, _ a1: Date, _ b0: Date, _ b1: Date) -> TimeInterval {
                max(0, min(a1, b1).timeIntervalSince(max(a0, b0)))
            }

            // an open locked visit only absorbs stays at its own place
            func isNear(_ c: Coordinate, _ v: Visit) throws -> Bool {
                let radius = try v.placeID.flatMap(store.place)?.radius ?? config.newPlaceRadius
                return Geo.distance(c, v.coordinate) <= max(radius, config.stayRadius) + config.placeMatchSlack
            }
            func setDeparture(_ lv: inout Visit, _ e: Date) throws {
                lv.departure = e
                lv.updatedAt = Date()
                try store.upsertVisit(lv)
                // keep the copy in sync so later stays aren't absorbed into the now-closed visit
                let id = lv.id
                if let i = lockedVisits.firstIndex(where: { $0.id == id }) { lockedVisits[i] = lv }
                try store.audit("visit", lv.id, "infer_departure", field: "departure_ts", old: nil, new: iso(e))
            }
            // a stop deleted while still open covers the stay it was, not everything up to now
            func deletedEnd(_ v: Visit) -> Date {
                if let d = v.departure { return d }
                guard let s = stays.first(where: {
                    $0.start <= v.arrival.addingTimeInterval(config.minStayDuration) && ($0.end ?? now) > v.arrival
                }) else { return v.arrival }
                return s.end ?? now
            }

            // 1. resolve each detected stay to a visit (locked, reused auto, or new)
            var resolved: [Visit] = []
            progress(.resolvingVisits, 0, of: stays.count)
            for (si, stay) in stays.enumerated() {
                if si > 0 && si % 20 == 0 { progress(.resolvingVisits, si, of: stays.count) }
                let sEnd = stay.end ?? now
                let sDur = max(1, sEnd.timeIntervalSince(stay.start))
                // showing up somewhere else ends an open locked visit ("still here" said later wins),
                // at the last fix still near it
                for var lv in lockedVisits where !lv.deleted && lv.departure == nil && lv.arrival < stay.start {
                    guard try !isNear(stay.centroid, lv),
                          try !(store.heldOpenAt(visitID: lv.id).map { $0 > stay.start } ?? false) else { continue }
                    let lastNear = try clean.filter { $0.timestamp > lv.arrival && $0.timestamp < stay.start }
                        .last { try isNear($0.coordinate, lv) }
                    try setDeparture(&lv, lastNear?.timestamp ?? stay.start)
                }
                // user said this time was travel, or deleted this stop
                if lockedTrips.contains(where: { !$0.deleted && overlap($0.departure, $0.arrival, stay.start, sEnd) > 0.5 * sDur })
                    || lockedVisits.contains(where: { $0.deleted && overlap($0.arrival, deletedEnd($0), stay.start, sEnd) > 0.5 * sDur }) {
                    continue
                }
                if var lv = lockedVisits.first(where: { !$0.deleted && overlap($0.arrival, $0.departure ?? now, stay.start, sEnd) > 0 }) {
                    // close at the end of this stay unless the next stay is back at the same place (GPS split),
                    // or the user marked "still here" after it ended
                    if lv.departure == nil, let e = stay.end,
                       try !(stays.indices.contains(si + 1) && isNear(stays[si + 1].centroid, lv)),
                       try !(store.heldOpenAt(visitID: lv.id).map { $0 > e } ?? false) {
                        try setDeparture(&lv, e)
                    }
                    if resolved.last?.id != lv.id { resolved.append(lv) } else { resolved[resolved.count - 1] = lv }
                    keptVisitIDs.insert(lv.id)
                    continue
                }
                let place = try resolvePlace(for: stay.centroid, report: &report)
                if let idx = reusableAuto.firstIndex(where: { overlap($0.arrival, $0.departure ?? now, stay.start, sEnd) > 0 }) {
                    var v = reusableAuto.remove(at: idx)
                    let changed = v.arrival != stay.start || v.departure != stay.end || v.placeID != place.id
                    v.arrival = stay.start; v.departure = stay.end; v.coordinate = stay.centroid
                    v.placeID = place.id; v.pointCount = stay.pointCount; v.autoConfidence = stay.confidence
                    if changed { v.updatedAt = Date(); report.visitsUpdated += 1 }
                    try store.upsertVisit(v)
                    resolved.append(v); keptVisitIDs.insert(v.id)
                } else {
                    let v = Visit(placeID: place.id, arrival: stay.start, departure: stay.end, coordinate: stay.centroid,
                                  autoConfidence: stay.confidence, source: .inferred, userStatus: .auto,
                                  timeZone: tzAt(stay.start, points: points), pointCount: stay.pointCount)
                    try store.upsertVisit(v)
                    resolved.append(v); keptVisitIDs.insert(v.id); report.visitsCreated += 1
                }
            }
            // locked (non-deleted) visits that weren't matched still belong in the sequence
            for lv in lockedVisits where !lv.deleted && !keptVisitIDs.contains(lv.id) {
                resolved.append(lv); keptVisitIDs.insert(lv.id)
            }
            resolved.sort { $0.arrival < $1.arrival }

            // 2. drop auto trips in the window; they are rebuilt below
            progress(.buildingTrips, stays.count, of: stays.count)
            for t in existingTrips where !t.userStatus.isLocked {
                try store.db.run("UPDATE flights SET trip_id = NULL WHERE trip_id = ?", t.id)
                try store.db.run("DELETE FROM trips WHERE id = ?", t.id)
                report.tripsRemoved += 1
            }
            // 3. remove auto visits that no detection supports any more
            for v in reusableAuto {
                for t in try store.tripsReferencing(visitID: v.id) where !t.userStatus.isLocked {
                    try store.db.run("UPDATE flights SET trip_id = NULL WHERE trip_id = ?", t.id)
                    try store.db.run("DELETE FROM trips WHERE id = ?", t.id)
                    report.tripsRemoved += 1
                }
                try store.db.run("DELETE FROM trips WHERE deleted = 1 AND user_status = 'auto' AND (origin_visit_id = ? OR destination_visit_id = ?)", v.id, v.id)
                try store.db.run("DELETE FROM visits WHERE id = ?", v.id)
                report.visitsRemoved += 1
            }

            // 4. link the visit that precedes the window, if it has no outgoing trip yet
            if let first = resolved.first,
               let prev = try store.db.query("""
                    SELECT * FROM visits WHERE deleted = 0 AND arrival_ts < ? ORDER BY arrival_ts DESC LIMIT 1
                    """, first.arrival).first.map(TravelStore.visit),
               prev.departure != nil,
               try store.tripsReferencing(visitID: prev.id).allSatisfy({ $0.originVisitID != prev.id }) {
                resolved.insert(prev, at: 0)
            }

            // 5. build trips between consecutive visits
            if resolved.count >= 2 {
                for i in 1..<resolved.count {
                    let a = resolved[i - 1], b = resolved[i]
                    guard let dep = a.departure, b.arrival > dep else { continue }
                    if lockedTrips.contains(where: { !$0.deleted && overlap($0.departure, $0.arrival, dep, b.arrival) > 0 }) { continue }
                    if try store.tripsReferencing(visitID: a.id).contains(where: { $0.originVisitID == a.id }) { continue }
                    let trip = try buildTrip(from: a, to: b, points: clean, motion: motion)
                    try store.upsertTrip(trip)
                    report.tripsCreated += 1
                    if trip.mode == .airplane { try linkFlight(for: trip, from: a, to: b) }
                }
            }
            // 6. attach each stamp to the visit that accounts for it (or none); stamps are otherwise never touched
            let finalVisits = try store.visits(overlapping: from.addingTimeInterval(-config.stampTimeTolerance),
                                               to.addingTimeInterval(config.stampTimeTolerance))
            for s in stamps { try store.setStampVisit(s.id, anchoring.visit(for: s, in: finalVisits, now: now)?.id) }
            try store.db.run("""
                UPDATE stamps SET visit_id = NULL
                WHERE visit_id IS NOT NULL AND visit_id NOT IN (SELECT id FROM visits WHERE deleted = 0)
                """)
            progress(.finalizing, stays.count, of: stays.count)
            try store.pruneOrphanPlaces()
            try store.pruneOrphanFlights()
        }
        try store.setMeta("last_inference_at", iso(now))
        return report
    }

    // MARK: - Helpers

    private func resolvePlace(for c: Coordinate, report: inout Report) throws -> Place {
        if let p = try store.matchPlace(c, slack: config.placeMatchSlack) {
            return p.mergedInto.flatMap { try? store.place($0) } ?? p
        }
        let p = Place(coordinate: c, radius: config.newPlaceRadius, source: .inferred)
        try store.upsertPlace(p)
        report.placesCreated += 1
        onPlaceCreated?(p)
        return p
    }

    func buildTrip(from a: Visit, to b: Visit, points: [RawPoint], motion: MotionTimeline) throws -> Trip {
        let dep = a.departure ?? a.arrival
        let arr = b.arrival
        var path = points.filter { $0.timestamp > dep && $0.timestamp < arr }
        path.insert(RawPoint(timestamp: dep, coordinate: a.coordinate, source: "anchor"), at: 0)
        path.append(RawPoint(timestamp: arr, coordinate: b.coordinate, source: "anchor"))

        let classifier = ModeClassifier(config: config)
        let segs = classifier.segment(path: path, motion: motion)
        let tripID = newID()
        let segments: [TripSegment] = segs.enumerated().map { i, s in
            TripSegment(tripID: tripID, sequence: i, start: s.start, end: s.end, modeAuto: s.mode,
                        modeConfidence: s.confidence, distance: s.distance,
                        routePolyline: Polyline.encode(Geo.simplify(s.coordinates, tolerance: config.routeSimplifyTolerance)))
        }
        var mode = ModeClassifier.mainMode(segs.map { ($0.mode, $0.end.timeIntervalSince($0.start), $0.distance) })
        var modeConf = segs.filter { $0.mode == mode }.map(\.confidence).max() ?? 0.2

        // personalisation: what the user chose before on this OD pair
        if let o = a.placeID, let d = b.placeID {
            let past = try store.correctedModes(originPlaceID: o, destinationPlaceID: d)
            if let top = mostCommon(past) {
                let share = Double(past.filter { $0 == top }.count) / Double(past.count)
                if share >= 0.6 && (past.count >= 2 || top.group == mode.group || mode == .unknown) {
                    mode = top
                    modeConf = min(0.9, 0.5 + 0.1 * Double(past.count)) * share
                }
            }
        }

        let coords = path.map(\.coordinate)
        let hasGap = zip(path, path.dropFirst()).contains { $1.timestamp.timeIntervalSince($0.timestamp) > config.gapThreshold }
        let density = Double(path.count - 2) / max(1, arr.timeIntervalSince(dep) / 60)   // points per minute
        let existence = hasGap ? 0.5 : min(0.95, 0.6 + 0.1 * density)
        return Trip(id: tripID, originVisitID: a.id, destinationVisitID: b.id, departure: dep, arrival: arr,
                    distance: Geo.pathLength(coords), modeAuto: mode, modeConfidence: modeConf.rounded(toPlaces: 2),
                    routePolyline: Polyline.encode(Geo.simplify(coords, tolerance: config.routeSimplifyTolerance)),
                    hasGap: hasGap, autoConfidence: existence.rounded(toPlaces: 2), source: .inferred, userStatus: .auto,
                    timeZone: a.timeZone, segments: segments)
    }

    private func linkFlight(for trip: Trip, from a: Visit, to b: Visit) throws {
        guard try store.flight(tripID: trip.id) == nil else { return }
        // a rebuilt trip gets a new id; re-attach the flight its predecessor left behind (keeps seat, number, notes)
        if var f = try store.unlinkedFlight(overlapping: trip.departure, trip.arrival) {
            f.tripID = trip.id
            try store.upsertFlight(f)
            return
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = trip.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let oPlace = try a.placeID.flatMap(store.place)
        let dPlace = try b.placeID.flatMap(store.place)
        let f = Flight(tripID: trip.id, date: fmt.string(from: trip.departure),
                       originCode: oPlace?.category == .airport ? oPlace?.code : nil,
                       destinationCode: dPlace?.category == .airport ? dPlace?.code : nil,
                       origin: a.coordinate, destination: b.coordinate, departure: trip.departure, arrival: trip.arrival,
                       distance: Geo.distance(a.coordinate, b.coordinate), source: .inferred)
        try store.upsertFlight(f)
    }

    private func tzAt(_ t: Date, points: [RawPoint]) -> String? {
        points.min { abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t)) }?.timeZone
            ?? TimeZone.current.identifier
    }
}

func mostCommon<T: Hashable>(_ xs: [T]) -> T? {
    var counts: [T: Int] = [:]
    for x in xs { counts[x, default: 0] += 1 }
    // stable: ties go to the earliest (most recent) element
    return xs.first { counts[$0] == counts.values.max() }
}

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func iso(_ d: Date?) -> String? { d.map { isoFormatter.string(from: $0) } }
