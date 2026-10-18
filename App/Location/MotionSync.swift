import Foundation
import HHTCore
#if os(iOS)
import CoreMotion
#endif

/// Pulls CoreMotion activity history (the OS keeps ~7 days) into `motion_activities`.
/// No continuous listening is needed: the history is queried whenever inference runs.
@MainActor
final class MotionSync {
    private let store: TravelStore
    #if os(iOS)
    private let manager = CMMotionActivityManager()
    #endif

    init(store: TravelStore) { self.store = store }

    static var isAvailable: Bool {
        #if os(iOS)
        return CMMotionActivityManager.isActivityAvailable()
        #else
        return false
        #endif
    }

    /// Triggers the Motion & Fitness permission prompt (via a tiny query) if not yet decided.
    func requestPermission() {
        #if os(iOS)
        guard Self.isAvailable else { return }
        manager.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { _, _ in }
        #endif
    }

    func sync() async {
        #if os(iOS)
        guard Self.isAvailable else { return }
        let now = Date()
        let oldest = now.addingTimeInterval(-7 * 86_400)
        let from = max(store.lastMotionDate() ?? oldest, oldest)
        let activities: [CMMotionActivity] = await withCheckedContinuation { cont in
            manager.queryActivityStarting(from: from, to: now, to: .main) { acts, _ in cont.resume(returning: acts ?? []) }
        }
        try? store.insertMotion(activities.map(Self.sample(from:)))
        #endif
    }

    #if os(iOS)
    static func sample(from a: CMMotionActivity) -> MotionSample {
        let kind: MotionSample.Activity
        if a.automotive { kind = .automotive }
        else if a.cycling { kind = .cycling }
        else if a.running { kind = .running }
        else if a.walking { kind = .walking }
        else if a.stationary { kind = .stationary }
        else { kind = .unknown }
        return MotionSample(timestamp: a.startDate, activity: kind, confidence: a.confidence.rawValue)
    }
    #endif
}
