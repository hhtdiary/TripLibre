#if targetEnvironment(simulator)
import Foundation
import HHTCore

/// Simulator-only: synthesises raw GPS + motion for the past few days (Philadelphia) so the UI can be exercised.
/// Compiled out of device builds so it can never mix fake points into a real history.
enum DemoData {
    static func generate(into store: TravelStore, days: Int = 3) throws {
        let home = Coordinate(39.9526, -75.1652), penn = Coordinate(39.9522, -75.1932)
        let lunch = Coordinate(39.9540, -75.2010), grocery = Coordinate(39.9480, -75.1700)
        let station = Coordinate(39.9530, -75.1680), exit = Coordinate(39.9545, -75.1890)
        var points: [RawPoint] = []
        var motion: [MotionSample] = []
        var rng = SystemRandomNumberGenerator()
        let cal = Calendar.current
        var t = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date()))!
        var here = home

        func jitter(_ c: Coordinate, _ m: Double) -> Coordinate {
            Geo.unproject((Double.random(in: -m...m, using: &rng), Double.random(in: -m...m, using: &rng)), origin: c)
        }
        func stay(_ minutes: Double) {
            motion.append(MotionSample(timestamp: t, activity: .stationary, confidence: 2))
            let end = t.addingTimeInterval(minutes * 60)
            for _ in 0..<6 where t < end {
                points.append(RawPoint(timestamp: t, coordinate: jitter(here, 12), horizontalAccuracy: 12, speed: 0, collectorMode: "moving"))
                t = t.addingTimeInterval(30)
            }
            points.append(RawPoint(timestamp: t, coordinate: jitter(here, 12), horizontalAccuracy: 12, speed: 0,
                                   source: "stationary_marker", collectorMode: "stationary"))
            t = max(t, end)
        }
        func move(_ to: Coordinate, speed: Double, _ activity: MotionSample.Activity, gps: Bool = true) {
            motion.append(MotionSample(timestamp: t, activity: activity, confidence: 2))
            let dur = Geo.distance(here, to) / speed
            let o = Geo.project(here, origin: here), e = Geo.project(to, origin: here)
            let start = t, origin = here
            var el = 10.0
            while el < dur {
                if gps {
                    let f = el / dur
                    points.append(RawPoint(timestamp: start.addingTimeInterval(el),
                                           coordinate: jitter(Geo.unproject((o.x + (e.x - o.x) * f, o.y + (e.y - o.y) * f), origin: origin), 6),
                                           horizontalAccuracy: 8, speed: speed, collectorMode: "moving"))
                }
                el += 10
            }
            t = start.addingTimeInterval(dur)
            here = to
        }

        for d in 0..<days {
            stay(8 * 60 + Double.random(in: 0...40, using: &rng))
            if d % 2 == 0 {
                move(station, speed: 1.4, .walking)
                move(exit, speed: 9, .automotive, gps: false)
                move(penn, speed: 1.4, .walking)
            } else {
                move(penn, speed: 4.5, .cycling)
            }
            stay(230)
            move(lunch, speed: 1.3, .walking)
            stay(45)
            move(penn, speed: 1.3, .walking)
            stay(210)
            move(grocery, speed: 8, .automotive)
            stay(20)
            move(home, speed: 1.4, .walking)
            let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t))!
            stay(max(30, midnight.timeIntervalSince(t) / 60))
        }
        // Two saved places in one building at the short afternoon stop, so reviewing it shows "Is this one of your
        // places?" with two choices GPS can't tell apart (issue #95). Categories that don't prompt for a cost.
        try store.upsertPlace(Place(id: "demo-dentist", name: "Dr. Lee", coordinate: grocery, radius: 60,
                                    category: .medical, unit: "Suite 400", source: .manual))
        try store.upsertPlace(Place(id: "demo-coworking", name: "Co-working", coordinate: Geo.unproject((6, 0), origin: grocery),
                                    radius: 60, category: .workSchool, unit: "Floor 5", source: .manual))
        try store.insertPoints(points.filter { $0.timestamp < Date() })
        try store.insertMotion(motion.filter { $0.timestamp < Date() })
    }
}
#endif
