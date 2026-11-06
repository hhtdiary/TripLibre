import Foundation
import Testing
@testable import HHTCore

@Suite("Schematic trip connections (#109)")
struct SchematicTripsTests {
    let home = ODFlows.Endpoint(key: "p:home", coordinate: Philly.home)
    let penn = ODFlows.Endpoint(key: "p:penn", coordinate: Philly.penn)
    let shop = ODFlows.Endpoint(key: "p:shop", coordinate: Philly.grocery)

    func leg(_ id: String, _ a: ODFlows.Endpoint?, _ b: ODFlows.Endpoint?, _ modes: TravelMode...) -> SchematicTrips.Leg {
        SchematicTrips.Leg(id: id, origin: a, destination: b, modes: modes.map { .init($0) })
    }

    @Test func everyModeHasAKindAndEveryKindABend() {
        for m in TravelMode.allCases { _ = SchematicTrips.kind(of: m) }
        let o = SchematicTrips.Options()
        for k in SchematicTrips.Kind.allCases { #expect(o.bend[k] != nil) }
        #expect(SchematicTrips.kind(of: .unknown) == .other && SchematicTrips.kind(of: .airplane) == .flight)
    }

    @Test func curvesJoinEndpointsInOrder() {
        let c = SchematicTrips.layout([leg("a", home, penn, .walk), leg("b", penn, shop, .bus)])
        #expect(c.map(\.order) == [1, 2])
        #expect(c[0].path.first == Philly.home && c[0].path.last == Philly.penn)
        #expect(c[1].spans.count == 1 && c[1].spans[0].kind == .bus)
        #expect(!c[0].isLoop)
    }

    @Test func deterministicAcrossRedraws() {
        let legs = [leg("a", home, penn, .car), leg("b", penn, home, .car), leg("c", home, home, .walk)]
        let first = SchematicTrips.layout(legs), again = SchematicTrips.layout(legs)
        #expect(first == again)
    }

    @Test func reciprocalTripsBowApart() {
        let c = SchematicTrips.layout([leg("a", home, penn, .car), leg("b", penn, home, .car)])
        // heading west bows north, heading east bows south
        #expect(c[0].marker.latitude > Philly.home.latitude)
        #expect(c[1].marker.latitude < Philly.home.latitude)
    }

    @Test func repeatedTripsFanOut() {
        let c = SchematicTrips.layout([leg("a", home, penn, .car), leg("b", home, penn, .car)])
        let mid = Coordinate((Philly.home.latitude + Philly.penn.latitude) / 2, (Philly.home.longitude + Philly.penn.longitude) / 2)
        #expect(Geo.distance(c[1].marker, mid) > Geo.distance(c[0].marker, mid) + 50)
    }

    @Test func flightsBowMoreThanRail() {
        let c = SchematicTrips.layout([leg("a", home, penn, .airplane), leg("b", shop, penn, .subway)])
        func bow(_ x: SchematicTrips.Connection) -> Double {
            let mid = Coordinate((x.origin.coordinate.latitude + x.destination.coordinate.latitude) / 2,
                                 (x.origin.coordinate.longitude + x.destination.coordinate.longitude) / 2)
            return Geo.distance(x.marker, mid) / Geo.distance(x.origin.coordinate, x.destination.coordinate)
        }
        #expect(bow(c[0]) > 2 * bow(c[1]))
    }

    @Test func roundTripsBecomeDistinctLoops() {
        let c = SchematicTrips.layout([leg("a", home, penn, .walk), leg("b", home, home, .walk), leg("c", home, home, .bicycle)])
        #expect(c[1].isLoop && c[2].isLoop)
        #expect(c[1].path.first == Philly.home && c[1].path.last == Philly.home)
        #expect(Geo.distance(c[1].marker, Philly.home) >= 40)
        #expect(Geo.distance(c[1].marker, c[2].marker) > 20)
    }

    @Test func snappedKeysAloneDoNotMakeARoundTrip() {
        // ~89 m apart, yet both snap to the same ~100 m grid key
        let a = ODFlows.Endpoint(coordinate: Coordinate(40.9996, -75)), b = ODFlows.Endpoint(coordinate: Coordinate(41.0004, -75))
        #expect(a.key == b.key)
        let c = SchematicTrips.layout([leg("t", a, b, .walk)])[0]
        #expect(!c.isLoop && c.path.last == b.coordinate)
        // the same saved place at both ends is still a round trip
        #expect(SchematicTrips.layout([leg("r", home, home, .walk)])[0].isLoop)
    }

    @Test func missingEndpointsAreLeftOutButKeepOrder() {
        let c = SchematicTrips.layout([leg("a", nil, penn, .walk), leg("b", penn, nil, .walk), leg("c", penn, shop, .walk)])
        #expect(c.map(\.id) == ["c"] && c[0].order == 3)
    }

    @Test func multimodalSplitsCurveByWeight() {
        let l = SchematicTrips.Leg(id: "m", origin: home, destination: penn,
                                   modes: [.init(.walk, weight: 1), .init(.subway, weight: 2), .init(.subway, weight: 1), .init(.walk, weight: 1)])
        let c = SchematicTrips.layout([l])[0]
        #expect(c.spans.map(\.mode) == [.walk, .subway, .walk])
        #expect(c.mainMode == .subway)
        #expect(c.spans[0].coordinates.first == c.path.first && c.spans[2].coordinates.last == c.path.last)
        #expect(c.spans[0].coordinates.last == c.spans[1].coordinates.first)
        let total = Geo.pathLength(c.path), walk = Geo.pathLength(c.spans[0].coordinates)
        #expect(abs(walk / total - 0.2) < 0.02)
    }

    @Test func legUsesPlacesThenVisitsThenRoute() {
        let place = Place(id: "P", coordinate: Philly.penn)
        let v1 = Visit(id: "v1", arrival: Date(), departure: Date(), coordinate: Philly.home)
        let v2 = Visit(id: "v2", placeID: "P", arrival: Date(), departure: Date(), coordinate: Philly.restaurant)
        let t = Trip(originVisitID: "v1", destinationVisitID: "v2", departure: Date(), arrival: Date(), distance: 1000,
                     modeAuto: .walk, modeConfidence: 1)
        let l = SchematicTrips.leg(for: t, visits: ["v1": v1, "v2": v2], places: ["P": place])
        #expect(l.origin?.coordinate == Philly.home && l.destination?.key == "p:P" && l.destination?.coordinate == Philly.penn)

        var stored = t
        stored.originVisitID = nil; stored.destinationVisitID = nil
        stored.routePolyline = Polyline.encode([Philly.grocery, Philly.phl])
        let s = SchematicTrips.leg(for: stored, visits: [:], places: [:])
        #expect(s.origin != nil && s.destination != nil)

        stored.routePolyline = nil
        let none = SchematicTrips.leg(for: stored, visits: [:], places: [:])
        #expect(none.origin == nil && none.destination == nil)
    }
}
