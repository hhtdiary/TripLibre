import Foundation
import Testing
@testable import HHTCore

@Suite("Collector stationary detection")
struct StationaryDetectorTests {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    let here = Coordinate(39.9526, -75.1652)

    func fix(_ dt: TimeInterval, _ c: Coordinate? = nil, speed: Double? = 0, acc: Double = 5) -> StationaryDetector.Fix {
        .init(timestamp: t0.addingTimeInterval(dt), coordinate: c ?? here, horizontalAccuracy: acc, speed: speed)
    }

    /// ~`metres` north of `here`.
    func north(_ metres: Double) -> Coordinate { Coordinate(here.latitude + metres / 111_195, here.longitude) }

    func motion(_ a: MotionSample.Activity, _ dt: TimeInterval = 0, confidence: Int = 2) -> MotionSample {
        MotionSample(timestamp: t0.addingTimeInterval(dt), activity: a, confidence: confidence)
    }

    // #expect cannot wrap mutating calls, hence these.
    func observe(_ d: inout StationaryDetector, _ f: StationaryDetector.Fix) -> Bool { d.observe(f) }
    func evaluate(_ d: inout StationaryDetector, _ dt: TimeInterval) -> StationaryDetector.Decision {
        d.evaluate(now: t0.addingTimeInterval(dt))
    }

    /// Evaluate once a minute from `from` to `to`, like the app's timer; returns the first time it switched.
    func tick(_ d: inout StationaryDetector, from: TimeInterval, to: TimeInterval) -> TimeInterval? {
        var t = from
        while t <= to {
            if evaluate(&d, t) == .enterStationary { return t }
            t += 60
        }
        return nil
    }

    @Test func restingPhoneGoesStationaryAfterDwell() {
        var d = StationaryDetector(now: t0)
        #expect(!observe(&d, fix(0, speed: 0.3)))
        d.observe(motion: motion(.stationary, 30))
        #expect(tick(&d, from: 60, to: 600) == 180)
    }

    @Test func fixesInsideRadiusCompleteTheDwell() {
        var d = StationaryDetector(now: t0)
        #expect(!observe(&d, fix(0)))
        #expect(!observe(&d, fix(100, north(30))))
        #expect(observe(&d, fix(185, north(40))))
    }

    @Test func movingFixResetsTheAnchor() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0))
        _ = d.observe(fix(150, north(200)))
        #expect(!observe(&d, fix(200, north(210))))       // only 50 s at the new anchor
        #expect(d.anchor?.timestamp == t0.addingTimeInterval(150))
    }

    /// Snapshot pattern (#46 §8): last fix at 25 m/s, then the app is suspended. Silence must not mean "arrived".
    @Test func silenceAfterFastFixDoesNotSwitch() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 25))
        #expect(tick(&d, from: 60, to: 540) == nil)
    }

    @Test func fastFixInsideRadiusDoesNotSwitch() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 0))
        #expect(!observe(&d, fix(200, north(20), speed: 8)))
    }

    @Test func automotiveMotionVetoesEvenAtLowSpeed() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 0.5))                  // stopped at a light
        d.observe(motion: motion(.automotive, -60))
        #expect(tick(&d, from: 60, to: 540) == nil)
    }

    @Test func lowConfidenceMotionDoesNotVeto() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 0.2))
        d.observe(motion: motion(.walking, 10, confidence: 0))
        #expect(tick(&d, from: 60, to: 300) == 180)
    }

    @Test func parkedCarSwitchesOnceMotionSaysStationary() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 1.0))
        d.observe(motion: motion(.automotive))
        #expect(tick(&d, from: 60, to: 240) == nil)
        d.observe(motion: motion(.stationary, 250))
        #expect(tick(&d, from: 300, to: 300) == 300)
    }

    @Test func silenceCapEventuallySwitches() {
        // no GPS in an underground garage after driving in fast; motion stuck on automotive
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 6))
        d.observe(motion: motion(.automotive))
        #expect(tick(&d, from: 60, to: 1200) == 600)
    }

    /// The timer firing on resume from suspension must wait for queued fixes before judging the silence.
    @Test func resumeFromSuspensionPostponesDecision() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 0.2))
        #expect(evaluate(&d, 60) == .stay)
        // suspended; the next timer tick runs 290 s later
        #expect(evaluate(&d, 350) == .recheck(after: 5))
        // the queued fix shows the phone is 2 km away
        #expect(!observe(&d, fix(349, north(2000), speed: 20)))
        #expect(evaluate(&d, 355) == .stay)
    }

    @Test func resumeWithoutNewFixesStillSwitchesWhenStill() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0, speed: 0.2))
        d.observe(motion: motion(.stationary))
        #expect(evaluate(&d, 60) == .stay)
        #expect(evaluate(&d, 350) == .recheck(after: 5))
        #expect(evaluate(&d, 355) == .enterStationary)
    }

    @Test func poorAccuracyFixesAreIgnored() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0))
        _ = d.observe(fix(100, north(500), acc: 300))
        #expect(d.anchor?.timestamp == t0)
        #expect(d.lastFix?.timestamp == t0)
    }

    @Test func resetClearsAnchor() {
        var d = StationaryDetector(now: t0)
        _ = d.observe(fix(0))
        d.reset(at: t0.addingTimeInterval(500))
        #expect(d.anchor == nil)
        #expect(evaluate(&d, 900) == .stay)
    }
}
