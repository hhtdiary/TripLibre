import Foundation
import Testing
@testable import HHTCore

@Suite("OD flow arcs")
struct ODFlowsTests {
    let home = ODFlows.Endpoint(key: "home", coordinate: Philly.home)
    let penn = ODFlows.Endpoint(key: "penn", coordinate: Philly.penn)
    let shop = ODFlows.Endpoint(key: "shop", coordinate: Philly.grocery)

    @Test func repeatedTripsMergeIntoOneWeightedFlow() {
        let flows = ODFlows.aggregate([
            (home, penn, .walk), (home, penn, .bus), (home, penn, .walk),
            (penn, home, .walk),
            (home, shop, .car),
        ])
        #expect(flows.count == 3)                                    // direction matters
        #expect(flows[0].id == "home→penn" && flows[0].trips == 3 && flows[0].mode == .walk)
        #expect(flows[1].trips == 1 && flows[2].mode == .car)
    }

    @Test func loopsAndTinyHopsDropped() {
        let nextDoor = ODFlows.Endpoint(key: "door", coordinate: Geo.unproject((40, 0), origin: Philly.home))
        #expect(ODFlows.aggregate([(home, home, .walk), (home, nextDoor, .walk)]).isEmpty)
    }

    @Test func unnamedEndpointsSnapToGrid() {
        let a = ODFlows.Endpoint(coordinate: Coordinate(39.95261, -75.16521))
        let b = ODFlows.Endpoint(coordinate: Coordinate(39.95264, -75.16519))
        #expect(a.key == b.key)
    }

    @Test func arcEndsAtODAndBowsRightOfTravel() {
        let arc = ODFlows.arc(from: Philly.home, to: Philly.penn)   // heading west
        #expect(arc.first == Philly.home && arc.last == Philly.penn)
        let apex = arc[arc.count / 2]
        #expect(apex.latitude > max(Philly.home.latitude, Philly.penn.latitude))   // right of westward = north
        // apex offset ≈ bend × distance
        let d = Geo.distance(Philly.home, Philly.penn)
        let off = Geo.distance(apex, Coordinate((Philly.home.latitude + Philly.penn.latitude) / 2,
                                                (Philly.home.longitude + Philly.penn.longitude) / 2))
        #expect(abs(off - 0.2 * d) < 0.02 * d)
    }

    @Test func returnTripFormsLensNotOverlap() {
        let out = ODFlows.arc(from: Philly.home, to: Philly.penn)
        let back = ODFlows.arc(from: Philly.penn, to: Philly.home)
        #expect(out[out.count / 2].latitude > Philly.home.latitude)
        #expect(back[back.count / 2].latitude < Philly.home.latitude)
    }
}
