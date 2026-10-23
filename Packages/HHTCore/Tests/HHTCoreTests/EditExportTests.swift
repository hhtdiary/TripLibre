import Foundation
import Testing
@testable import HHTCore

/// home → penn → restaurant → penn → home, all walking.
private func chainDay() -> Trajectory {
    var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
    tr.stay(minutes: 60)
    tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
    tr.stay(minutes: 180)
    tr.move(to: Philly.restaurant, speed: 1.3, activity: .walking)
    tr.stay(minutes: 45)
    tr.move(to: Philly.penn, speed: 1.3, activity: .walking)
    tr.stay(minutes: 180)
    tr.move(to: Philly.home, speed: 1.4, activity: .walking)
    tr.stay(minutes: 60)
    return tr
}

private func processed(_ tr: Trajectory, path: String = ":memory:") throws -> (TravelStore, InferenceEngine) {
    let store = try TravelStore(path: path)
    try store.insertPoints(tr.points)
    try store.insertMotion(tr.motion)
    let engine = InferenceEngine(store: store)
    try engine.processNew(now: tr.t.addingTimeInterval(60))
    return (store, engine)
}

@Suite("Editing, persistence, export")
struct EditExportTests {

    @Test func modeEditSurvivesReprocessing() throws {
        let tr = chainDay()
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let trips = try store.allTrips()
        try edit.setTripMode(trips[0].id, .bicycle)
        try engine.process(from: .distantPast, to: tr.t, now: tr.t.addingTimeInterval(60))
        let after = try store.allTrips()
        #expect(after.count == trips.count)
        #expect(after.first { $0.id == trips[0].id }?.mode == .bicycle)
        #expect(after.first { $0.id == trips[0].id }?.modeAuto == .walk)   // automatic value preserved
        #expect(try store.auditLog(entityID: trips[0].id).contains { $0.action == "set_mode" && $0.newValue == "bicycle" })
    }

    @Test func deleteVisitMergesTripsAndStaysDeleted() throws {
        let tr = chainDay()
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let visits = try store.allVisits()
        #expect(visits.count == 5)
        let restaurant = visits[2]
        try edit.deleteVisit(restaurant.id)
        var trips = try store.allTrips()
        #expect(trips.count == 3)
        #expect(trips[1].originVisitID == visits[1].id && trips[1].destinationVisitID == visits[3].id)
        // reprocessing must not resurrect the stop
        try engine.process(from: .distantPast, to: tr.t, now: tr.t.addingTimeInterval(60))
        trips = try store.allTrips()
        #expect(try store.allVisits().count == 4)
        #expect(trips.count == 3)
        #expect(try store.visit(restaurant.id)?.deleted == true)           // soft delete, still in DB
    }

    @Test func deleteTripMergesVisits() throws {
        let tr = chainDay()
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let trips = try store.allTrips()
        // delete penn → restaurant: restaurant visit is absorbed into penn visit
        try edit.deleteTrip(trips[1].id)
        #expect(try store.allTrips().count == 3)
        #expect(try store.allVisits().count == 4)
        try engine.process(from: .distantPast, to: tr.t, now: tr.t.addingTimeInterval(60))
        #expect(try store.allTrips().count == 3)
        let remaining = try store.allTrips()
        #expect(remaining[1].originVisitID == trips[1].originVisitID)       // relinked to surviving visit
    }

    @Test func deletePlaceRemovesItsVisitsAndStaysDeleted() throws {
        let tr = chainDay()
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let visits = try store.allVisits()
        let penn = try #require(visits[1].placeID)
        #expect(visits[3].placeID == penn)
        #expect(try store.places().count == 3)
        try edit.deletePlace(penn)
        #expect(try store.places().map(\.id).contains(penn) == false)
        #expect(try store.place(penn)?.deleted == true)                     // soft delete, still in DB
        #expect(try store.visits(atPlace: penn).isEmpty)
        // home → restaurant → home, trips joined across both penn stops
        #expect(try store.allVisits().map(\.id) == [visits[0].id, visits[2].id, visits[4].id])
        #expect(try store.allTrips().count == 2)
        #expect(try store.matchPlace(Philly.penn) == nil)
        #expect(throws: EditError.self) { try edit.setVisitPlace(visits[2].id, placeID: penn) }
        #expect(throws: EditError.self) { try edit.deletePlace(penn) }
        #expect(try store.auditLog(entityID: penn).contains { $0.action == "delete" && $0.newValue == "2" })
        // reprocessing must not resurrect the place or its stops
        try engine.process(from: .distantPast, to: tr.t, now: tr.t.addingTimeInterval(60))
        #expect(try store.allVisits().count == 3)
        #expect(try store.allTrips().count == 2)
        #expect(try store.places().count == 2)
        // the export leaves it out too
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-delplace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try Exporter(store: store).exportBundle(to: dir)
        let csv = try String(contentsOf: folder.appendingPathComponent("places.csv"), encoding: .utf8)
        #expect(!csv.contains(penn))
    }

    @Test func namedPlaceRecognisedAgain() throws {
        var tr = chainDay()
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let penn = try store.allVisits()[1]
        let place = try edit.createPlace(forVisit: penn.id, name: "Penn", category: .workSchool, radius: 150)
        // next day: new data, same place
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        tr.stay(minutes: 120)
        try store.insertPoints(tr.points.filter { $0.timestamp > (store.lastPoint()?.timestamp ?? .distantPast) })
        try store.insertMotion(tr.motion)
        try engine.processNew(now: tr.t.addingTimeInterval(60))
        #expect(try store.allVisits().last?.placeID == place.id)
    }

    @Test func splitVisitAndSplitTrip() throws {
        let tr = chainDay()
        let (store, _) = try processed(tr)
        let edit = EditService(store: store)
        let visits = try store.allVisits()
        let penn = visits[1]
        let leave = penn.arrival.addingTimeInterval(3600), back = leave.addingTimeInterval(1800)
        let created = try edit.splitVisit(penn.id, leave: leave, back: back, mode: .walk)
        #expect(created.count == 1)
        #expect(try store.allVisits().count == 6)
        #expect(try store.allTrips().count == 5)

        let t = try store.allTrips().last!
        let mid = t.departure.addingTimeInterval(t.duration / 2)
        let stop = try edit.splitTrip(t.id, stopStart: mid, stopEnd: mid.addingTimeInterval(1), placeID: nil)
        let all = try store.allTrips()
        #expect(all.count == 6)
        #expect(all.contains { $0.destinationVisitID == stop.id } && all.contains { $0.originVisitID == stop.id })
    }

    // Issue #11: the split sheets crashed on open because their picker ranges were built from `Date()` defaults
    // (now…a past departure). The defaults must be ordered and strictly inside the record for any record length.
    @Test(arguments: [0.5, 5, 90, 3 * 3600] as [TimeInterval])
    func splitDefaultsAreOrderedInsideTheRecord(span: TimeInterval) {
        let a = Trajectory.date("2026-09-15 07:00"), d = a.addingTimeInterval(span)
        for (dep, now) in [(Optional(d), Date()), (nil, d)] {   // past visit; still-open visit
            let v = SplitTimes.visit(arrival: a, departure: dep, now: now)
            #expect(a < v.leave && v.leave < v.back && v.back < d)
            #expect(v.leave <= v.stopArrival && v.stopArrival <= v.stopDeparture && v.stopDeparture <= v.back)
        }
        let t = SplitTimes.trip(departure: a, arrival: d)
        #expect(a < t.stopStart && t.stopStart <= t.stopEnd && t.stopEnd < d)
        let picked = SplitTimes.tripStop(start: t.stopStart, end: t.stopStart, arrival: d)
        #expect(picked.stopStart <= picked.stopEnd && picked.stopEnd < d)
        #expect(ClosedRange<Date>.ordered(d, a) == d...d)
    }

    @Test func splitDefaultsAreAcceptedByEditService() throws {
        let (store, _) = try processed(chainDay())
        let edit = EditService(store: store)
        let lunch = try edit.createPlace(forVisit: try store.allVisits()[2].id, name: "Lunch", category: nil)

        // "I left and came back", via a stop, on an inferred visit
        let penn = try store.allVisits()[1]
        let v = SplitTimes.visit(arrival: penn.arrival, departure: penn.departure)
        let created = try edit.splitVisit(penn.id, leave: v.leave, back: v.back,
                                          stop: (lunch.id, v.stopArrival, v.stopDeparture), mode: .walk)
        #expect(created.count == 2)

        // "I stopped somewhere" on a user-edited (locked) trip, with the picker's zero-length stop padded
        var trip = try store.allTrips()[0]
        try edit.setTripMode(trip.id, .bicycle)
        trip = try #require(try store.trip(trip.id))
        let t = SplitTimes.trip(departure: trip.departure, arrival: trip.arrival)
        let s = SplitTimes.tripStop(start: t.stopStart, end: t.stopStart, arrival: trip.arrival)
        let stop = try edit.splitTrip(trip.id, stopStart: s.stopStart, stopEnd: s.stopEnd)
        let halves = try store.allTrips().filter { $0.destinationVisitID == stop.id || $0.originVisitID == stop.id }
        #expect(halves.count == 2 && halves.allSatisfy { $0.mode == .bicycle && $0.departure < $0.arrival })
    }

    @Test func splitTripAtMapPin() throws {
        let (store, _) = try processed(chainDay())
        let edit = EditService(store: store)
        let trip = try store.allTrips()[0]   // home → penn
        let mid = trip.departure.addingTimeInterval(trip.duration / 2)
        // A pin far from where GPS was at `mid` must win over the GPS guess.
        let stop = try edit.splitTrip(trip.id, stopStart: mid, stopEnd: mid.addingTimeInterval(300), at: Philly.restaurant)
        #expect(Geo.distance(stop.coordinate, Philly.restaurant) < 1)
        let place = try #require(try store.place(stop.placeID!))
        #expect(Geo.distance(place.coordinate, Philly.restaurant) < 50)
    }

    @Test func correctionsPersistAcrossRestart() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hht-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tr = chainDay()
        var tripID = ""
        do {
            let (store, _) = try processed(tr, path: path)
            let edit = EditService(store: store)
            tripID = try store.allTrips()[0].id
            try edit.setTripMode(tripID, .ebike)
            try edit.setVisitPurpose(try store.allVisits()[2].id, .meal)
        }
        let reopened = try TravelStore(path: path)
        #expect(try reopened.trip(tripID)?.mode == .ebike)
        #expect(try reopened.allVisits()[2].purpose == .meal)
        #expect(reopened.schemaVersion == Schema.migrations.count)
    }

    @Test func personalisedModeFromCorrections() throws {
        // Home→Penn at 8 m/s without motion data looks like a car; the user says e-bike twice.
        var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
        tr.stay(minutes: 60, activity: nil)
        for _ in 0..<2 {
            tr.move(to: Philly.penn, speed: 8)
            tr.stay(minutes: 120, activity: nil)
            tr.move(to: Philly.home, speed: 8)
            tr.stay(minutes: 120, activity: nil)
        }
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let trips = try store.allTrips()
        #expect(trips.count == 4)
        #expect(trips[0].mode == .car)
        for t in trips { try edit.setTripMode(t.id, .ebike) }
        // third commute: learned from corrections
        tr.move(to: Philly.penn, speed: 8)
        tr.stay(minutes: 60, activity: nil)
        try store.insertPoints(tr.points.filter { $0.timestamp > (store.lastPoint()?.timestamp ?? .distantPast) })
        try engine.processNew(now: tr.t.addingTimeInterval(60))
        let last = try store.allTrips().last!
        #expect(last.userStatus == .auto)
        #expect(last.mode == .ebike)
    }

    @Test func exportBundle() throws {
        let tr = chainDay()
        let (store, _) = try processed(tr)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-export-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try Exporter(store: store).exportBundle(to: dir)
        for f in ["trips.csv", "trip_segments.csv", "visits.csv", "places.csv", "flights.csv", "data.json",
                  "places.geojson", "trips.geojson", "trip_ends.geojson", "travel.sqlite", "raw_location_points.csv", "README.txt"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(f).path), "\(f)")
        }
        let trips = CSV.parseRecords(try String(contentsOf: folder.appendingPathComponent("trips.csv"), encoding: .utf8))
        #expect(trips.count == 4)
        #expect(trips.map { $0["trip_seq"] } == ["1", "2", "3", "4"])
        let visits = CSV.parseRecords(try String(contentsOf: folder.appendingPathComponent("visits.csv"), encoding: .utf8))
        let visitIDs = Set(visits.compactMap { $0["visit_id"] })
        #expect(trips.allSatisfy { visitIDs.contains($0["origin_visit_id"] ?? "") && visitIDs.contains($0["destination_visit_id"] ?? "") })
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("data.json"))) as? [String: Any]
        #expect((json?["trips"] as? [Any])?.count == 4)
        let gj = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("trips.geojson"))) as? [String: Any]
        #expect((gj?["features"] as? [Any])?.count == 4)
        // the SQLite snapshot opens and has the same data
        let snap = try TravelStore(path: folder.appendingPathComponent("travel.sqlite").path)
        #expect(try snap.allTrips().count == 4)
        let viewRows = try snap.db.query("SELECT mode_final FROM v_trips")
        #expect(viewRows.count == 4)
    }

    /// When HHT_EXPORT_DIR is set (CI / `make export-check`), write a real export there so the Python
    /// loader in analysis/ can be tested against the app's actual output format.
    @Test func writeExportForPythonCheck() throws {
        guard let dir = ProcessInfo.processInfo.environment["HHT_EXPORT_DIR"] else { return }
        let tr = chainDay()
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let v = try store.allVisits()
        try edit.createPlace(forVisit: v[0].id, name: "Home", category: .home)
        try edit.createPlace(forVisit: v[1].id, name: "Penn", category: .workSchool)
        try edit.setTripMode(try store.allTrips()[0].id, .bicycle)
        // one stamp at Penn (attached by the next run) so the contract check covers stamps.csv
        let tap = v[1].arrival.addingTimeInterval(600)
        try edit.addStamp(at: tap, fix: v[1].coordinate, fixAccuracy: 30, fixTime: tap)
        try engine.process(from: tr.points[0].timestamp, to: tr.t, now: tr.t.addingTimeInterval(60))
        // a cost on the first trip and one at Penn, so the contract check covers expenses.csv
        let first = try store.allTrips().sorted { $0.departure < $1.departure }[0]
        try edit.saveExpense(Expense(timestamp: first.departure, amount: 2.9, currency: "USD", category: .fare, tripID: first.id))
        try edit.saveExpense(Expense(timestamp: tap, amount: 4.5, currency: "USD", category: .food, visitID: v[1].id))
        let folder = try Exporter(store: store).exportBundle(to: URL(fileURLWithPath: dir))
        print("HHT export written to \(folder.path)")
    }

    @Test func importTripsAndFlights() throws {
        let store = try TravelStore.inMemory()
        let imp = Importer(store: store)
        let airports = """
        id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,continent,iso_country,iso_region,municipality,scheduled_service,gps_code,iata_code,local_code,home_link,wikipedia_link,keywords
        1,KPHL,large_airport,Philadelphia International Airport,39.871899,-75.241096,36,NA,US,US-PA,Philadelphia,yes,KPHL,PHL,PHL,,,
        2,KSLC,large_airport,Salt Lake City International Airport,40.785749,-111.979746,4227,NA,US,US-UT,Salt Lake City,yes,KSLC,SLC,SLC,,,
        """
        #expect(try imp.importAirports(csv: airports) == 2)
        let res = try imp.importTrips(csv: """
        date,start_time,end_time,origin,destination,mode,distance_km,purpose,notes
        2026-08-18,08:00,10:30,PHL,SLC,airplane,,travel,"first trip, west"
        2026-08-19,23:30,00:15,Somewhere,Elsewhere,car_driver,12.5,,
        """, defaultTimeZone: TimeZone(identifier: "America/New_York")!)
        #expect(res.imported == 2)
        let trips = try store.allTrips()
        #expect(trips.count == 2)
        #expect(trips[0].mode == .airplane && trips[0].distance > 3_000_000)
        #expect(trips[1].duration == 45 * 60)                              // crossed midnight
        #expect(trips[1].notes?.contains("origin: Somewhere") == true)
        #expect(try store.flights().count == 1)
        let f = try imp.importFlights(csv: "date,origin,destination,airline,flight_number\n2026-08-25,SLC,PHL,DL,1234\n")
        #expect(f.imported == 1)
        #expect(Analytics.flightStats(try store.flights()).routes["PHL–SLC"] == 2)
    }

    @Test func gpxImport() throws {
        let store = try TravelStore.inMemory()
        let gpx = """
        <?xml version="1.0"?><gpx version="1.1"><trk><trkseg>
        <trkpt lat="39.95" lon="-75.16"><ele>10</ele><time>2026-01-01T10:00:00Z</time></trkpt>
        <trkpt lat="39.96" lon="-75.17"><time>2026-01-01T10:05:00.500Z</time></trkpt>
        </trkseg></trk></gpx>
        """
        let r = try Importer(store: store).importGPX(Data(gpx.utf8))
        #expect(r.count == 2)
        #expect(store.pointCount() == 2)
    }
}

@Suite("Geometry and analytics")
struct GeoAnalyticsTests {
    @Test func polylineRoundTrip() {
        let c = [Coordinate(38.5, -120.2), Coordinate(40.7, -120.95), Coordinate(43.252, -126.453)]
        #expect(Polyline.encode(c) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        let d = Polyline.decode(Polyline.encode(c))
        #expect(zip(c, d).allSatisfy { abs($0.latitude - $1.latitude) < 1e-5 && abs($0.longitude - $1.longitude) < 1e-5 })
    }

    @Test func distances() {
        // one degree of longitude on the equator = 2πR/360
        #expect(abs(Geo.distance(Coordinate(0, 0), Coordinate(0, 1)) - 2 * .pi * Geo.earthRadius / 360) < 0.01)
        #expect(abs(Geo.distance(Coordinate(0, 0), Coordinate(90, 0)) - .pi * Geo.earthRadius / 2) < 0.01)
        let rg = Geo.radiusOfGyration([Coordinate(0, 0), Coordinate(0, 0.02)])!
        #expect(abs(rg - Geo.distance(Coordinate(0, 0), Coordinate(0, 0.02)) / 2) < 1)
        let hull = Geo.convexHull([Coordinate(0, 0), Coordinate(0, 0.01), Coordinate(0.01, 0.01), Coordinate(0.01, 0), Coordinate(0.005, 0.005)])
        #expect(hull.hull.count == 4)
        #expect(abs(hull.areaSquareMeters / 1_236_000 - 1) < 0.02)
    }

    @Test func csvParsing() {
        let rows = CSV.parse("a,b\n\"x, y\",\"he said \"\"hi\"\"\"\r\n1,\n")
        #expect(rows == [["a", "b"], ["x, y", "he said \"hi\""], ["1", ""]])
    }

    @Test func metrics() throws {
        let tr = chainDay()
        let (store, _) = try processed(tr)
        let edit = EditService(store: store)
        let v = try store.allVisits()
        try edit.createPlace(forVisit: v[0].id, name: "Home", category: .home)
        try edit.setVisitPlace(v[4].id, placeID: try store.visit(v[0].id)!.placeID!)
        let m = try Analytics.compute(store: store, range: DateRange(start: .distantPast, end: tr.t), now: tr.t)
        #expect(m.trips == 4)
        #expect(m.personDays == 1)
        #expect(m.modeShare.first?.mode == .walk)
        #expect(m.uniquePlaces == 3)
        #expect(m.tours == 1)
        #expect(m.meanStopsPerTour == 3)
        #expect(m.complexTourShare == 1)
        #expect((m.radiusOfGyrationDwell ?? 0) > 500)
        #expect(m.departuresByHour.reduce(0, +) == 4)
        #expect(m.topODPairs.count == 4)
    }

    /// A corrected trip that departs before the incremental window still pins its destination visit:
    /// dropping that auto visit used to hit the trips → visits foreign key.
    @Test func lockedTripBeforeWindowPinsItsDestination() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.grocery, speed: 8, activity: .automotive)
        tr.stay(minutes: 30)
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        let (store, engine) = try processed(tr)
        let grocery = try #require(try store.allVisits().last)
        // an auto visit no detection supports, reached by a user-corrected trip that departs before it
        let orphan = Visit(arrival: tr.t.addingTimeInterval(-300), departure: tr.t.addingTimeInterval(-120),
                           coordinate: Philly.restaurant)
        try store.upsertVisit(orphan)
        let trip = Trip(originVisitID: grocery.id, destinationVisitID: orphan.id,
                        departure: try #require(grocery.departure), arrival: orphan.arrival,
                        distance: 1000, modeAuto: .walk, modeConfidence: 0.5, modeUser: .taxi, userStatus: .edited)
        try store.upsertTrip(trip)
        try engine.processNew(now: tr.t.addingTimeInterval(60))
        #expect(try store.visit(orphan.id) != nil)
        #expect(try store.allTrips().first { $0.id == trip.id }?.mode == .taxi)
    }

    /// "Still here" is an override: reprocessing must not close the visit again at the old detected end.
    @Test func stillHereSurvivesReprocessing() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.grocery, speed: 8, activity: .automotive)
        tr.stay(minutes: 60)
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let grocery = try #require(try store.allVisits().first { Geo.distance($0.coordinate, Philly.grocery) < 100 })
        #expect(grocery.departure != nil)
        try edit.setVisitTimes(grocery.id, arrival: grocery.arrival, departure: nil)
        try engine.process(from: .distantPast, to: tr.t, now: tr.t.addingTimeInterval(60))
        #expect(try store.visit(grocery.id)?.departure == nil)
    }

    /// A pinned, still-open visit must not swallow a later stay somewhere else.
    @Test func openLockedVisitClosesWhenYouShowUpElsewhere() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.grocery, speed: 8, activity: .automotive)
        tr.stay(minutes: 10)
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        try edit.setTripMode(try #require(try store.allTrips().last).id, .subway)   // pins the open grocery visit
        let grocery = try #require(try store.allVisits().last)
        #expect(grocery.departure == nil)
        let leave = tr.t
        tr.move(to: Philly.penn, speed: 8, activity: .automotive)
        tr.stay(minutes: 30)
        try store.insertPoints(tr.points.filter { $0.timestamp > (store.lastPoint()?.timestamp ?? .distantPast) })
        try store.insertMotion(tr.motion.filter { $0.timestamp > leave })
        try engine.processNew(now: tr.t.addingTimeInterval(60))
        let dep = try #require(try store.visit(grocery.id)?.departure)
        #expect(abs(dep.timeIntervalSince(leave)) < 120)
        let visits = try store.allVisits()
        #expect(visits.count == 3)
        #expect(Geo.distance(visits[2].coordinate, Philly.penn) < 100)
        #expect(try store.allTrips().count == 2)
    }

    /// Deleting a stop while it is still open must not suppress every later stay (Atlanta, Oct 1).
    @Test func deletedOpenVisitDoesNotSwallowLaterStays() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.grocery, speed: 8, activity: .automotive)
        tr.stay(minutes: 20)
        let (store, engine) = try processed(tr)
        let edit = EditService(store: store)
        let grocery = try #require(try store.allVisits().last)
        #expect(grocery.departure == nil)
        try edit.deleteVisit(grocery.id)
        let leave = tr.t
        tr.move(to: Philly.penn, speed: 8, activity: .automotive)
        tr.stay(minutes: 30)
        tr.move(to: Philly.restaurant, speed: 1.3, activity: .walking)
        tr.stay(minutes: 30)
        try store.insertPoints(tr.points.filter { $0.timestamp > (store.lastPoint()?.timestamp ?? .distantPast) })
        try store.insertMotion(tr.motion.filter { $0.timestamp > leave })
        try engine.processNew(now: tr.t.addingTimeInterval(60))
        let visits = try store.allVisits()
        #expect(visits.count == 3)
        #expect(!visits.contains { Geo.distance($0.coordinate, Philly.grocery) < 100 })
        #expect(Geo.distance(visits[1].coordinate, Philly.penn) < 100)
        #expect(Geo.distance(visits[2].coordinate, Philly.restaurant) < 100)
        #expect(try store.visit(grocery.id)?.deleted == true)
    }

    /// Issue #35: a segment the user sets by hand ("Subway / metro + Walk") is kept as a segment-level record.
    @Test func manualSegmentsPersistAndStayContiguous() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hht-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tr = chainDay()
        var tripID = ""
        do {
            let (store, engine) = try processed(tr, path: path)
            let edit = EditService(store: store)
            let trip = try store.allTrips(withSegments: true)[0]
            tripID = trip.id
            #expect(trip.segments.count == 1)
            try edit.setSegmentMode(trip.segments[0].id, .subway)
            let change = trip.departure.addingTimeInterval(trip.duration * 0.7)
            let walk = try edit.addModeChange(tripID: tripID, at: change, mode: .walk)
            var t = try #require(try store.trip(tripID))
            #expect(t.displayModes == [.subway, .walk])
            #expect(t.mode == .subway && t.userStatus == .edited)
            #expect(t.segments.map(\.id).last == walk.id && t.segments.allSatisfy(\.isUserSet))
            #expect(t.segments.first?.start == t.departure && t.segments.last?.end == t.arrival)
            #expect(t.segments[0].end == change && t.segments[1].start == change)
            #expect(abs(t.segments.map(\.distance).reduce(0, +) - t.distance) < 0.2 * t.distance)

            // confirming the main mode (the ✓ chip) keeps both segments
            try edit.setTripMode(tripID, t.mode)
            #expect(try store.trip(tripID)?.displayModes == [.subway, .walk])

            // re-running inference neither erases nor duplicates them
            try engine.process(from: .distantPast, to: tr.t, now: tr.t.addingTimeInterval(60))
            t = try #require(try store.trip(tripID))
            #expect(t.displayModes == [.subway, .walk] && t.segments.count == 2 && t.segments[1].id == walk.id)
            #expect(try store.allTrips().filter { $0.departure < t.arrival && $0.arrival > t.departure }.count == 1)

            // move the boundary; a boundary on the trip's end or on an existing boundary is refused
            let later = change.addingTimeInterval(30)
            try edit.setSegmentEnd(t.segments[0].id, to: later)
            #expect(throws: EditError.self) { try edit.setSegmentEnd(t.segments[0].id, to: t.arrival) }
            #expect(throws: EditError.self) { try edit.addModeChange(tripID: tripID, at: later, mode: .bus) }
        }
        // the edits survive an app relaunch
        let reopened = try TravelStore(path: path)
        let edit = EditService(store: reopened)
        var t = try #require(try reopened.trip(tripID))
        #expect(t.displayModes == [.subway, .walk])
        #expect(t.segments.map(\.sequence) == [0, 1] && t.segments[0].end == t.segments[1].start)

        // remove the walk segment: the subway segment takes its time back
        try edit.removeSegment(t.segments[1].id)
        t = try #require(try reopened.trip(tripID))
        #expect(t.segments.count == 1 && t.segments[0].mode == .subway && t.segments[0].end == t.arrival)
        #expect(throws: EditError.self) { try edit.removeSegment(t.segments[0].id) }
        #expect(try reopened.auditLog(entityID: tripID).contains { $0.action == "split_segment" })
    }

    @Test func wholeTripModeAndResetOnMultimodalTrip() throws {
        let (store, _) = try processed(chainDay())
        let edit = EditService(store: store)
        let trip = try store.allTrips()[0]
        try edit.addModeChange(tripID: trip.id, at: trip.departure.addingTimeInterval(trip.duration / 2), mode: .bus)
        #expect(try store.trip(trip.id)?.displayModes == [.walk, .bus])
        // "it was all bicycle" replaces the segment modes but keeps the boundaries
        try edit.setTripMode(trip.id, .bicycle)
        var t = try #require(try store.trip(trip.id))
        #expect(t.displayModes == [.bicycle] && t.segments.count == 2)
        // back to automatic: the inferred segment returns to its own mode, the hand-made one keeps the last one set
        try edit.setTripMode(trip.id, nil)
        t = try #require(try store.trip(trip.id))
        #expect(t.segments.map(\.mode) == [.walk, .bicycle] && t.modeUser != nil)
        // an older whole-trip override that no segment carries still wins on display
        t.modeUser = .ferry
        #expect(t.displayModes == [.ferry])
    }

    @Test func modeChangeOnTripWithoutSegments() throws {
        let store = try TravelStore(path: ":memory:")
        let edit = EditService(store: store)
        let a = Place(name: "A", coordinate: Philly.home), b = Place(name: "B", coordinate: Philly.penn)
        try store.upsertPlace(a); try store.upsertPlace(b)
        let dep = Trajectory.date("2026-09-15 18:08")
        let trip = try edit.addManualTrip(originPlaceID: a.id, destinationPlaceID: b.id, departure: dep,
                                          arrival: dep.addingTimeInterval(300), mode: .subway, distance: 2250)
        try edit.addModeChange(tripID: trip.id, at: dep.addingTimeInterval(240), mode: .walk)
        let t = try #require(try store.trip(trip.id))
        #expect(t.displayModes == [.subway, .walk] && t.userStatus == .manual)
        #expect(abs(t.segments[0].distance - 1800) < 1 && abs(t.segments[1].distance - 450) < 1)
        #expect(t.segments.allSatisfy { $0.routePolyline != nil })
    }
}
