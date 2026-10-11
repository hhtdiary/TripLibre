import Foundation
import Testing
@testable import HHTCore

/// Point `east`/`north` metres from Philly.home.
private func at(_ east: Double, _ north: Double) -> Coordinate {
    Geo.unproject((east, north), origin: Philly.home)
}

@Suite("Route display cleanup")
struct RouteDisplayTests {

    @Test func straightRouteKeptIntact() {
        let route = stride(from: 0.0, through: 2000, by: 100).map { at($0, 0) }
        let pieces = RouteDisplay.clean(route, hasGap: false)
        #expect(pieces.count == 1)
        #expect(pieces[0].first == route.first && pieces[0].last == route.last)
    }

    @Test func spikeRemoved() {
        // walk east along a street; one fix jumps 1.5 km north and back
        var route = stride(from: 0.0, through: 1000, by: 100).map { at($0, 0) }
        route.insert(at(550, 1500), at: 6)
        let piece = RouteDisplay.clean(route, hasGap: false)[0]
        #expect(!piece.contains(at(550, 1500)))
        #expect(piece.allSatisfy { abs(Geo.project($0, origin: Philly.home).y) < 1 })
    }

    @Test func realTurnsKept() {
        // an L-shaped route around a block is not a spike
        let route = [at(0, 0), at(400, 0), at(400, 400), at(800, 400)]
        #expect(RouteDisplay.clean(route, hasGap: false) == [route])
    }

    @Test func stationaryDriftHidden() {
        let route = [at(0, 0), at(20, 15), at(-25, 30), at(10, -20), at(5, 5)]
        #expect(RouteDisplay.clean(route, hasGap: false).isEmpty)
    }

    @Test func stayJitterTrimmed() {
        let route = [at(0, 0), at(30, 20), at(-20, 25), at(15, -30), at(200, 0), at(600, 0),
                     at(1000, 0), at(1020, 30), at(990, -25), at(1000, 5)]
        let piece = RouteDisplay.clean(route, hasGap: false)[0]
        #expect(piece == [at(0, 0), at(200, 0), at(600, 0), at(1000, 5)])
    }

    @Test func gapConnectorSplitOnlyWhenTripHasGap() {
        let west = stride(from: 0.0, through: 500, by: 50).map { at($0, 0) }
        let east = stride(from: 6000.0, through: 6500, by: 50).map { at($0, 3000) }
        let route = west + east
        let split = RouteDisplay.clean(route, hasGap: true)
        #expect(split.count == 2)
        #expect(split[0].last == west.last && split[1].first == east.first)
        #expect(RouteDisplay.clean(route, hasGap: false).count == 1)
    }

    @Test func zoomedOutSimplifiesMore() {
        let zigzag = (0...200).map { i in at(Double(i) * 20, i.isMultiple(of: 2) ? 0 : 12) }
        let piece = RouteDisplay.clean(zigzag, hasGap: false)[0]
        let close = RouteDisplay.simplify(piece, metersPerPoint: 2)
        let far = RouteDisplay.simplify(piece, metersPerPoint: 50)
        #expect(far.count < close.count)
        #expect(far.count == 2)
        #expect(far.first == zigzag.first && far.last == zigzag.last)
    }
}
