import Foundation
import CoreLocation
import HHTCore
#if os(iOS)
import CoreMotion
#endif

/// Adaptive, low-power background location collection (docs/collection.md).
///
/// * **moving**: continuous updates (≈10 m accuracy, 15 m distance filter).
/// * **stationary**: after ~3 min within 60 m, at walking speed or slower and not contradicted by CoreMotion
///   (`StationaryDetector`), standard updates stop. A geofence around the stop,
///   CLVisit monitoring and significant-location-change monitoring wake the app (even after termination)
///   when the user leaves, and the collector switches back to moving.
///
/// Every fix is written to `raw_location_points` immediately; nothing is ever edited or discarded there.
@MainActor
final class LocationCollector: NSObject, ObservableObject {
    enum Mode: String { case off, moving, stationary }
    enum Profile: String, CaseIterable, Identifiable {
        case balanced, precise
        var id: String { rawValue }
        var label: String { self == .balanced ? "Balanced" : "Precise (more battery)" }
    }

    @Published private(set) var mode: Mode = .off
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var lastFix: Date?
    @Published private(set) var pointsToday = 0

    var profile: Profile = .balanced { didSet { if mode == .moving { applyMoving() } } }
    /// Called when the collector believes the user has arrived somewhere (good moment to run inference).
    var onStationary: (() -> Void)?

    private let manager = CLLocationManager()
    private let store: TravelStore
    private var anchor: CLLocation?
    private var detector = StationaryDetector()
    private var timer: Timer?
    private var recheck: Timer?
    #if os(iOS)
    /// Declares ongoing background location use (iOS 17+). Without it the app was suspended a few seconds into each
    /// background wake while driving, giving ~10 s GPS bursts every ~5 min (significant-change wakes).
    private var backgroundSession: CLBackgroundActivitySession?
    private let motionManager = CMMotionActivityManager()
    private var motionUpdatesRunning = false
    #endif
    private let regionID = "hht.stationary.region"

    static let departureDistance: CLLocationDistance = 150

    init(store: TravelStore) {
        self.store = store
        self.authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "trackingEnabled") as? Bool ?? true }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        #if os(iOS)
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        #endif
        default: break
        }
    }

    func start() {
        UserDefaults.standard.set(true, forKey: "trackingEnabled")
        guard authorizationAllowsCollection else { requestPermission(); return }
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        // Created on every start, including background relaunches: that continues the session begun in the foreground.
        if backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
        manager.startMonitoringVisits()
        #endif
        manager.startMonitoringSignificantLocationChanges()
        enterMoving(reason: "start")
        startMotionUpdatesIfAuthorized()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStationary() }
        }
    }

    /// Live activity feeds the stationary decision. Only when already authorized (MotionSync asks for permission),
    /// so this is also called once that prompt resolves and whenever the app becomes active. Idempotent.
    func startMotionUpdatesIfAuthorized() {
        #if os(iOS)
        guard mode != .off, !motionUpdatesRunning, CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .authorized
        else { return }
        motionUpdatesRunning = true
        motionManager.startActivityUpdates(to: .main) { [weak self] a in
            guard let a else { return }
            MainActor.assumeIsolated { self?.detector.observe(motion: MotionSync.sample(from: a)) }
        }
        #endif
    }

    func stop() {
        UserDefaults.standard.set(false, forKey: "trackingEnabled")
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        #if os(iOS)
        manager.stopMonitoringVisits()
        motionManager.stopActivityUpdates()
        motionUpdatesRunning = false
        backgroundSession?.invalidate()
        backgroundSession = nil
        #endif
        for r in manager.monitoredRegions { manager.stopMonitoring(for: r) }
        timer?.invalidate()
        recheck?.invalidate()
        mode = .off
    }

    /// Call on launch (including background relaunch by the OS).
    func resumeIfEnabled() {
        if isEnabled && authorizationAllowsCollection { start() }
    }

    private var authorizationAllowsCollection: Bool {
        #if os(iOS)
        return authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        #else
        return authorization == .authorizedAlways
        #endif
    }

    var authorizationLabel: String {
        switch authorization {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        #if os(iOS)
        case .authorizedWhenInUse: return "While using (background limited)"
        #endif
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Modes

    private func applyMoving() {
        manager.desiredAccuracy = profile == .precise ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = profile == .precise ? 5 : 15
    }

    private func enterMoving(reason: String) {
        if let r = manager.monitoredRegions.first(where: { $0.identifier == regionID }) { manager.stopMonitoring(for: r) }
        applyMoving()
        manager.startUpdatingLocation()
        mode = .moving
        anchor = nil
        detector.reset(at: Date())
    }

    private func enterStationary() {
        guard mode == .moving, let a = anchor else { return }
        recheck?.invalidate()
        mode = .stationary
        // mark the transition with the last fix so inference knows the following silence is deliberate
        record(a, source: "stationary_marker", at: Date())
        manager.stopUpdatingLocation()
        let region = CLCircularRegion(center: a.coordinate, radius: Self.departureDistance, identifier: regionID)
        region.notifyOnExit = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
        onStationary?()
    }

    private func checkStationary() {
        guard mode == .moving, anchor != nil else { return }
        switch detector.evaluate(now: Date()) {
        case .stay: break
        case .enterStationary: enterStationary()
        case .recheck(let delay):
            // just resumed from suspension: let queued fixes arrive before judging the silence
            recheck?.invalidate()
            recheck = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.checkStationary() }
            }
        }
    }

    // MARK: - Recording

    private func record(_ loc: CLLocation, source: String, at time: Date? = nil) {
        guard loc.horizontalAccuracy >= 0 else { return }
        let p = RawPoint(timestamp: time ?? loc.timestamp,
                         coordinate: Coordinate(loc.coordinate.latitude, loc.coordinate.longitude),
                         horizontalAccuracy: loc.horizontalAccuracy,
                         altitude: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
                         verticalAccuracy: loc.verticalAccuracy >= 0 ? loc.verticalAccuracy : nil,
                         speed: loc.speed >= 0 ? loc.speed : nil,
                         speedAccuracy: loc.speedAccuracy >= 0 ? loc.speedAccuracy : nil,
                         course: loc.course >= 0 ? loc.course : nil,
                         source: source, collectorMode: mode == .stationary ? "stationary" : "moving",
                         timeZone: TimeZone.current.identifier)
        do {
            try store.insertPoint(p)
            lastFix = p.timestamp
            pointsToday += 1
        } catch {
            NSLog("HHT: failed to store point: \(error)")
        }
    }

    private func handle(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 500 else { return }
        record(loc, source: mode == .stationary ? "significant_change" : "gps")
        switch mode {
        case .stationary:
            if let a = anchor, loc.distance(from: a) > Self.departureDistance, loc.horizontalAccuracy < 200 {
                enterMoving(reason: "moved")
            }
        case .moving:
            let fix = StationaryDetector.Fix(timestamp: loc.timestamp,
                                             coordinate: Coordinate(loc.coordinate.latitude, loc.coordinate.longitude),
                                             horizontalAccuracy: loc.horizontalAccuracy,
                                             speed: loc.speed >= 0 ? loc.speed : nil)
            let still = detector.observe(fix)
            if detector.anchor == fix { anchor = loc }
            if still { enterStationary() }
        case .off:
            break
        }
    }
}

extension LocationCollector: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in for l in locations { self.handle(l) } }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            #if os(iOS)
            if status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            #endif
            if self.isEnabled && self.authorizationAllowsCollection && self.mode == .off { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            if let l = manager.location, Date().timeIntervalSince(l.timestamp) < 120 { self.record(l, source: "region_exit") }
            self.enterMoving(reason: "region exit")
        }
    }

    #if os(iOS)
    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            let c = Coordinate(visit.coordinate.latitude, visit.coordinate.longitude)
            if visit.arrivalDate != .distantPast {
                _ = try? self.store.insertPoint(RawPoint(timestamp: visit.arrivalDate, coordinate: c,
                                                     horizontalAccuracy: visit.horizontalAccuracy, source: "visit_arrival",
                                                     collectorMode: "stationary"))
            }
            if visit.departureDate != .distantFuture {
                _ = try? self.store.insertPoint(RawPoint(timestamp: visit.departureDate, coordinate: c,
                                                     horizontalAccuracy: visit.horizontalAccuracy, source: "visit_departure",
                                                     collectorMode: "stationary"))
                if self.mode == .stationary { self.enterMoving(reason: "visit departure") }
            }
        }
    }
    #endif

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("HHT: location error \(error)")
    }
}
