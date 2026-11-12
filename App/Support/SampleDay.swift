import Foundation
import HHTCore

/// The tutorial's sample day (issue #114): a walk to a friend's that was guessed as a car trip, the stop there, and the
/// walk back home, which a wait at a crossing split in two with a stop that never was. Two things to fill in (name,
/// category, purpose) and two inference mistakes to correct (the mode, the phantom stop).
///
/// It exists only as values in memory while the tutorial is on screen. Nothing here is written to a `TravelStore`, so
/// sample stops and trips can never reach the diary, the stats, the widgets, a backup or an export.
struct SampleDay: Equatable {
    /// What the learner has set so far.
    var placeName = ""
    var category: PlaceCategory?
    var purpose: TripPurpose?
    var mode: TravelMode?
    /// The stop inference made up on the way home has been removed ("This wasn't a stop").
    var phantomRemoved = false

    static let phantomID = "sample-visit-crossing"
    static let returnTripID = "sample-trip-back"
    static let stopID = "sample-visit-friend"
    static let tripID = "sample-trip-out"
    /// What "inference" got wrong, on purpose: 1.7 km in 24 minutes is walking pace.
    static let guessedMode = TravelMode.car
    static let tripDistance = 1700.0
    static let tripDuration: TimeInterval = 24 * 60

    static var exampleName: String { L("Mingming's Home") }
    static let exampleCategory = PlaceCategory.friendFamily
    static let examplePurpose = TripPurpose.social
    static let exampleMode = TravelMode.walk

    static let categories: [PlaceCategory] = [.friendFamily, .home, .cafe, .workSchool]
    static let purposes: [TripPurpose] = [.social, .meal, .escort, .work]
    static let modes: [TravelMode] = [.walk, .bicycle, .bus, .car]

    var trimmedName: String { placeName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The purpose the diary row shows: the one chosen for this visit, else the one the place's category suggests.
    var shownPurpose: TripPurpose? { purpose ?? category?.defaultPurpose }

    /// Writes the day into a throwaway store (in memory, see `TutorialView`), so the app's real detail screens can
    /// open on it. Each trip gets its schematic curve as its "recorded" route, to have a line on the trip's map.
    func seed(_ store: TravelStore, day: Date) throws {
        let d = data(on: day)
        for p in d.places.values { try store.upsertPlace(p) }
        for v in d.visitsByID.values { try store.upsertVisit(v) }
        for var t in d.trips {
            if let c = d.connections.first(where: { $0.id == t.id }) { t.routePolyline = Polyline.encode(c.path) }
            try store.upsertTrip(t)
        }
    }

    /// Takes back what the learner changed on the real screens, so the tutorial carries on from there.
    mutating func read(from store: TravelStore) {
        if let v = try? store.visit(Self.stopID), !v.deleted {
            purpose = v.purpose
            if let p = v.placeID.flatMap({ try? store.place($0) }) {
                placeName = p.name ?? ""
                category = p.category
            }
        }
        if let t = try? store.trip(Self.tripID), !t.deleted {
            mode = t.modeUser ?? (t.userStatus == .auto ? nil : t.mode)
        }
        if !phantomRemoved {
            let v = try? store.visit(Self.phantomID)
            phantomRemoved = v == nil || v?.deleted == true
        }
    }

    /// The day as the diary screens draw it, with the learner's edits applied.
    func data(on day: Date) -> DayData {
        let start = Calendar.current.startOfDay(for: day)
        func at(_ hour: Int, _ minute: Int) -> Date { start.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        // two residential blocks in Philadelphia, about a mile apart (the real pages show them on a map)
        let homeAt = Coordinate(39.9466, -75.1592), friendAt = Coordinate(39.9481, -75.1772)

        let home = Place(id: "sample-home", name: L("Home"), coordinate: homeAt, category: .home, source: .manual)
        let friend = Place(id: "sample-friend", name: trimmedName.isEmpty ? nil : trimmedName, coordinate: friendAt,
                           category: category)
        let touched = !trimmedName.isEmpty || category != nil || purpose != nil

        let morning = Visit(id: "sample-visit-morning", placeID: home.id, placeStatus: .confirmed, arrival: at(8, 0),
                            departure: at(10, 10), coordinate: homeAt, userStatus: .confirmed)
        let stop = Visit(id: Self.stopID, placeID: friend.id, placeStatus: touched ? .confirmed : .auto,
                         arrival: at(10, 34), departure: at(13, 5), coordinate: friendAt, purpose: purpose,
                         userStatus: touched ? .edited : .auto)
        let evening = Visit(id: "sample-visit-evening", placeID: home.id, placeStatus: .confirmed, arrival: at(13, 28),
                            departure: at(18, 0), coordinate: homeAt, userStatus: .confirmed)

        let out = Trip(id: Self.tripID, originVisitID: morning.id, destinationVisitID: stop.id, departure: at(10, 10),
                       arrival: at(10, 10).addingTimeInterval(Self.tripDuration), distance: Self.tripDistance,
                       modeAuto: Self.guessedMode, modeConfidence: 0.42, modeUser: mode,
                       userStatus: mode == nil ? .auto : (mode == Self.guessedMode ? .confirmed : .edited))
        // The way home. Inference saw a six-minute wait at a crossing and cut the walk in two around a stop; removing
        // that stop joins the halves, as `EditService.deleteVisit` does in the real diary.
        let crossingAt = Coordinate(39.9473, -75.1689)
        let crossing = Place(id: "sample-crossing", coordinate: crossingAt, address: "S 17th St")
        let phantom = Visit(id: Self.phantomID, placeID: crossing.id, arrival: at(13, 14), departure: at(13, 20),
                            coordinate: crossingAt, autoConfidence: 0.35)
        let backTrips: [Trip]
        if phantomRemoved {
            backTrips = [Trip(id: Self.returnTripID, originVisitID: stop.id, destinationVisitID: evening.id,
                              departure: at(13, 5), arrival: at(13, 28), distance: Self.tripDistance, modeAuto: .walk,
                              modeConfidence: 0.93, userStatus: .edited)]
        } else {
            backTrips = [Trip(id: Self.returnTripID, originVisitID: stop.id, destinationVisitID: phantom.id,
                              departure: at(13, 5), arrival: at(13, 14), distance: 800, modeAuto: .walk, modeConfidence: 0.93),
                         Trip(id: "sample-trip-back-2", originVisitID: phantom.id, destinationVisitID: evening.id,
                              departure: at(13, 20), arrival: at(13, 28), distance: Self.tripDistance - 800, modeAuto: .walk,
                              modeConfidence: 0.93)]
        }

        var d = DayData()
        // The morning at home is only the first trip's origin, like a stay that began the day before: leaving its row
        // out keeps the map and the stop being edited on one screen.
        d.visits = phantomRemoved ? [stop, evening] : [stop, phantom, evening]
        d.trips = [out] + backTrips
        d.places = [home.id: home, friend.id: friend, crossing.id: crossing]
        for v in [morning] + d.visits { d.visitsByID[v.id] = v }
        d.connections = SchematicTrips.layout(d.trips.map { SchematicTrips.leg(for: $0, visits: d.visitsByID, places: d.places) })
        d.items = (d.visits.map { DiaryItem.visit($0, $0.placeID.flatMap { d.places[$0] }) } + d.trips.map { DiaryItem.trip($0) })
            .sorted { $0.start < $1.start }
        return d
    }
}
