import Foundation
import Testing
@testable import HHTCore

/// Point `east`/`north` metres from Philly.home.
private func at(_ east: Double, _ north: Double) -> Coordinate {
    Geo.unproject((east, north), origin: Philly.home)
}

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

private func fix(_ seconds: Double, _ east: Double, _ north: Double, acc: Double? = 10) -> RawPoint {
    RawPoint(timestamp: t0.addingTimeInterval(seconds), coordinate: at(east, north), horizontalAccuracy: acc)
}

/// A walk east at 1.4 m/s with a fix every 10 s, starting `from` metres east at `start` seconds.
private func walk(from: Double = 0, metres: Double, start: Double = 0, north: Double = 0) -> [RawPoint] {
    stride(from: 0.0, through: metres, by: 14).enumerated().map { i, d in
        fix(start + Double(i) * 10, from + d, north)
    }
}

private func allOnLine(_ pieces: [[Coordinate]], north: Double, tolerance: Double = 1) -> Bool {
    pieces.allSatisfy { $0.allSatisfy { abs(Geo.project($0, origin: Philly.home).y - north) < tolerance } }
}

@Suite("Display trajectory (issue #100)")
struct DisplayTrajectoryTests {

    @Test func continuousWalkIsOnePiece() {
        let pts = walk(metres: 1400)
        let pieces = DisplayTrajectory.pieces(pts)
        #expect(pieces.count == 1)
        #expect(pieces[0].first == pts.first?.coordinate && pieces[0].last == pts.last?.coordinate)
    }

    @Test func timestampGapLeavesAGap() {
        // walk, 12 min of silence, then resume 600 m further north: no straight connector across the silence
        let before = walk(metres: 700)
        let after = walk(from: 900, metres: 700, start: before.last!.timestamp.timeIntervalSince(t0) + 720, north: 600)
        let pieces = DisplayTrajectory.pieces(before + after)
        #expect(pieces.count == 2)
        #expect(pieces[0].last == before.last?.coordinate && pieces[1].first == after.first?.coordinate)
    }

    @Test func poorAccuracyFixesNotDrawn() {
        // Wi-Fi / cell fixes 400 m off the street with 300 m accuracy: the street line stays straight
        var pts = walk(metres: 1400)
        pts[30] = fix(300, 420, 400, acc: 300)
        pts[31] = fix(310, 434, 380, acc: 250)
        let pieces = DisplayTrajectory.pieces(pts)
        #expect(pieces.count == 1)
        #expect(allOnLine(pieces, north: 0))
    }

    @Test func missingAccuracyIsKept() {
        let pts = walk(metres: 700).map { var p = $0; p.horizontalAccuracy = nil; return p }
        #expect(DisplayTrajectory.pieces(pts).count == 1)
    }

    @Test func isolatedJumpRemoved() {
        // "33rd St": one fix lands 900 m away and the next is back on the route
        var pts = walk(metres: 1400)
        pts[50] = fix(500, 700, 900)
        let pieces = DisplayTrajectory.pieces(pts)
        #expect(pieces.count == 1)
        #expect(allOnLine(pieces, north: 0))
    }

    @Test func repeatedTriangleArtifactsRemoved() {
        // "Broad/Market": several separate fixes snap to the same wrong corner ~350 m away, forming triangles
        var pts = walk(metres: 2100)
        for i in [20, 60, 100, 140] { pts[i] = fix(Double(i) * 10, 300, 350, acc: 30) }
        let pieces = DisplayTrajectory.pieces(pts)
        #expect(pieces.count == 1)
        #expect(allOnLine(pieces, north: 0))
    }

    @Test func implausibleConnectionSplit() {
        // two fixes 5 km apart 20 s apart with no return: not a spike, so the line is broken rather than drawn
        let a = walk(metres: 700)
        let s = a.last!.timestamp.timeIntervalSince(t0) + 20
        let b = walk(from: 5000, metres: 700, start: s, north: 3000)
        let pieces = DisplayTrajectory.pieces(a + b)
        #expect(pieces.count == 2)
    }

    @Test func highSpeedRailIsKept() {
        // 300 km/h (83 m/s), a fix every 15 s along a straight line
        let pts = (0...60).map { i in fix(Double(i) * 15, Double(i) * 1250, 0) }
        let pieces = DisplayTrajectory.pieces(pts)
        #expect(pieces.count == 1)
        #expect(pieces[0].first == pts.first?.coordinate && pieces[0].last == pts.last?.coordinate)
    }

    @Test func carCornerIsNotASpike() {
        // a car turns a corner at 15 m/s with a fix every 20 s: legs of 300 m, a genuine L-shape
        let pts = [fix(0, 0, 0), fix(20, 300, 0), fix(40, 300, 300), fix(60, 600, 300)]
        #expect(DisplayTrajectory.pieces(pts) == [pts.map(\.coordinate)])
    }

    @Test func tripUsesRawFixesAndAnchors() {
        // stored route has a jump the raw fixes explain as a gap; the drawn trip keeps the anchors, drops the connector
        let leg1 = walk(from: 20, metres: 600, start: 10)
        let leg2 = walk(from: 1200, metres: 600, start: 1200, north: 800)
        let dep = t0, arr = leg2.last!.timestamp.addingTimeInterval(10)
        let origin = at(0, 0), dest = at(1820, 800)
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: dep, arrival: arr, distance: 0,
                        modeAuto: .walk, modeConfidence: 0.8,
                        routePolyline: Polyline.encode([origin] + (leg1 + leg2).map(\.coordinate) + [dest]),
                        hasGap: true)
        let outside = [fix(-60, -500, -500), fix(arr.timeIntervalSince(t0) + 60, 3000, 3000)]
        let pieces = DisplayTrajectory.pieces(for: trip, points: outside[0..<1] + leg1 + leg2 + outside[1...])
        // measured, then an arc across the gap, then measured
        #expect(pieces.map(\.isConnector) == [false, true, false])
        #expect(pieces.allSatisfy { $0.mode == .walk })
        #expect(pieces[0].coordinates.first == trip.route.first)
        #expect(pieces[2].coordinates.last == trip.route.last)
        #expect(pieces[1].coordinates.first == pieces[0].coordinates.last)
        #expect(pieces[1].coordinates.last == pieces[2].coordinates.first)
    }

    @Test func segmentsColouredByMode() {
        let walkPts = walk(from: 20, metres: 420, start: 10)
        let s0 = walkPts.last!.timestamp.timeIntervalSince(t0)
        let busPts = (1...20).map { i in fix(s0 + Double(i) * 10, 434 + Double(i) * 80, 0) }
        let arr = busPts.last!.timestamp.addingTimeInterval(10)
        let mid = walkPts.last!.timestamp.addingTimeInterval(5)
        var trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: arr, distance: 0,
                        modeAuto: .bus, modeConfidence: 0.8, routePolyline: Polyline.encode([at(0, 0), at(2050, 0)]))
        trip.segments = [
            TripSegment(tripID: trip.id, sequence: 0, start: t0, end: mid, modeAuto: .walk, modeConfidence: 0.8, distance: 440),
            TripSegment(tripID: trip.id, sequence: 1, start: mid, end: arr, modeAuto: .bus, modeConfidence: 0.8, distance: 1600),
        ]
        let pieces = DisplayTrajectory.pieces(for: trip, points: walkPts + busPts)
        #expect(pieces.map(\.mode) == [.walk, .bus])
        // adjacent segments meet: the bus piece starts at the walk's last fix
        #expect(pieces[1].coordinates.first == walkPts.last?.coordinate)
    }

    @Test func carCadenceIsNotAGap() {
        // the collector samples cars every ~5 min (p90 291 s on real days): 4 km chords at 13 m/s stay joined
        let pts = (0...6).map { i in fix(Double(i) * 300, Double(i) * 4000, 0) }
        #expect(DisplayTrajectory.pieces(pts, mode: .car).count == 1)
    }

    @Test func subwayTunnelLeavesAGap() {
        // underground: no fix for 2–4 min while covering kilometres; the straight line between stations is not drawn
        let platform = (0...4).map { i in fix(Double(i) * 5, Double(i) * 5, 0) }
        let surface = (0...4).map { i in fix(200 + Double(i) * 5, 2600 + Double(i) * 5, 1200) }
        #expect(DisplayTrajectory.pieces(platform + surface, mode: .subway).count == 2)
        // the same shape by road is ordinary sparse sampling
        #expect(DisplayTrajectory.pieces(platform + surface, mode: .car).count == 1)
    }

    @Test func nextSegmentDoesNotRedrawPreviousConnector() {
        // real day (33rd St): a subway segment is a single 2.6 km tunnel connector from the origin, then a walk.
        // The walk must start at the boundary fix, not reach back to the origin and draw the connector itself.
        let origin = at(0, 0)
        let boundary = t0.addingTimeInterval(121)
        let walkPts = walk(from: 2600, metres: 560, start: 121, north: -1200)
        let arr = walkPts.last!.timestamp.addingTimeInterval(10)
        var trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: arr, distance: 0,
                        modeAuto: .subway, modeConfidence: 0.7,
                        routePolyline: Polyline.encode([origin] + walkPts.map(\.coordinate) + [at(3170, -1200)]))
        trip.segments = [
            TripSegment(tripID: trip.id, sequence: 0, start: t0, end: boundary, modeAuto: .subway, modeConfidence: 0.7, distance: 2600),
            TripSegment(tripID: trip.id, sequence: 1, start: boundary, end: arr, modeAuto: .walk, modeConfidence: 0.7, distance: 570),
        ]
        let pieces = DisplayTrajectory.pieces(for: trip, points: walkPts)
        // the tunnel is an arc in subway colour, the walk is measured from the boundary fix
        #expect(pieces.map(\.mode) == [.subway, .walk])
        #expect(pieces.map(\.isConnector) == [true, false])
        #expect(pieces[1].coordinates.first == walkPts.first?.coordinate)
        #expect(pieces[0].coordinates.count > 2)   // curved, not a straight connector
    }

    @Test func connectorArcBowsOutButMeetsBothEnds() {
        let a = at(0, 0), b = at(2000, 0)
        let arc = DisplayTrajectory.arc(from: a, to: b, bulge: 0.15)
        #expect(arc.first == a && arc.last == b)
        let peak = arc.map { Geo.project($0, origin: Philly.home).y }.max() ?? 0
        #expect(abs(peak - 300) < 5)   // 15 % of 2 km, to the left of travel (north when heading east)
    }

    @Test func shortGapGetsNoConnector() {
        // loose ends 30 m apart are left alone
        let a = walk(metres: 420)
        let b = walk(from: 450, metres: 420, start: a.last!.timestamp.timeIntervalSince(t0) + 700)
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0.addingTimeInterval(-1),
                        arrival: b.last!.timestamp.addingTimeInterval(1), distance: 0, modeAuto: .walk, modeConfidence: 0.8,
                        routePolyline: Polyline.encode([a[0].coordinate, b[b.count - 1].coordinate]))
        let pieces = DisplayTrajectory.pieces(for: trip, points: a + b)
        #expect(pieces.count == 2 && !pieces.contains { $0.isConnector })
    }

    @Test func flightKeepsStoredLine() {
        let route = [at(0, 0), at(800_000, 300_000)]
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: t0.addingTimeInterval(7200),
                        distance: 850_000, modeAuto: .airplane, modeConfidence: 0.9, routePolyline: Polyline.encode(route))
        #expect(DisplayTrajectory.pieces(for: trip, points: []) == [.init(mode: .airplane, coordinates: trip.route)])
    }

    @Test func manualTripWithoutFixesKeepsStoredLine() {
        let route = [at(0, 0), at(2000, 0)]
        let trip = Trip(originVisitID: nil, destinationVisitID: nil, departure: t0, arrival: t0.addingTimeInterval(3600),
                        distance: 2000, modeAuto: .car, modeConfidence: 1, routePolyline: Polyline.encode(route),
                        source: .manual)
        #expect(DisplayTrajectory.pieces(for: trip, points: []) == [.init(mode: .car, coordinates: trip.route)])
    }

    @Test func inferredTripWithoutFixesGetsOnlyAnArc() {
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: t0.addingTimeInterval(3600),
                        distance: 5000, modeAuto: .car, modeConfidence: 0.4,
                        routePolyline: Polyline.encode([at(0, 0), at(5000, 0)]), hasGap: true)
        let pieces = DisplayTrajectory.pieces(for: trip, points: [])
        #expect(pieces.count == 1)
        #expect(pieces[0].isConnector && pieces[0].mode == .car)
        #expect(pieces[0].coordinates.first == trip.route.first && pieces[0].coordinates.last == trip.route.last)
    }

    @Test func shortTripWithoutFixesIsAnArcNotAMeasuredLine() {
        // review on #107: a 5-min, 1 km trip's two stop anchors are within every gap threshold, but they are not a
        // measurement, so the trip is a connector arc rather than a solid line
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: t0.addingTimeInterval(300),
                        distance: 1000, modeAuto: .car, modeConfidence: 0.4,
                        routePolyline: Polyline.encode([at(0, 0), at(1000, 0)]))
        let pieces = DisplayTrajectory.pieces(for: trip, points: [])
        #expect(pieces.count == 1 && pieces[0].isConnector && pieces[0].mode == .car)
    }

    @Test func tripWhoseFixesAreAllRejectedIsAnArc() {
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: t0.addingTimeInterval(300),
                        distance: 1000, modeAuto: .walk, modeConfidence: 0.4,
                        routePolyline: Polyline.encode([at(0, 0), at(1000, 0)]))
        let poor = [fix(100, 300, 50, acc: 400), fix(200, 700, -40, acc: 250)]
        let pieces = DisplayTrajectory.pieces(for: trip, points: poor)
        #expect(pieces.count == 1 && pieces[0].isConnector)
    }

    @Test func isolatedFixesAreKeptAsArcWaypoints() {
        // review on #107: a subway trip sampled every 3 min, each fix its own run; the arcs must pass through the
        // observed station instead of collapsing to one origin-to-destination arc
        let station = at(1500, 800)
        let trip = Trip(originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: t0.addingTimeInterval(360),
                        distance: 3000, modeAuto: .subway, modeConfidence: 0.7,
                        routePolyline: Polyline.encode([at(0, 0), at(3000, 0)]))
        let pieces = DisplayTrajectory.pieces(for: trip, points: [fix(180, 1500, 800)])
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { $0.isConnector && $0.mode == .subway })
        #expect(pieces[0].coordinates.last == station && pieces[1].coordinates.first == station)
        #expect(pieces[0].coordinates.first == trip.route.first && pieces[1].coordinates.last == trip.route.last)
    }

    @Test func rawPointsAreNotMutated() {
        var pts = walk(metres: 700)
        pts[20] = fix(200, 300, 900, acc: 400)
        let copy = pts
        _ = DisplayTrajectory.pieces(pts)
        #expect(pts == copy)
    }
}
