import Foundation
import Combine
import CoreLocation
import HHTCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Writes the widgets' snapshot into the App Group whenever the diary or tracking state changes (issue #47).
/// Coalesces bursts and only asks WidgetKit to reload when the content actually changed, to spare the reload budget.
@MainActor
final class WidgetBridge {
    static let appGroup = "group.com.zyang91.hht"

    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(WidgetSnapshot.fileName)
    }

    private weak var model: AppModel?
    private var last: WidgetSnapshot?
    private var pending: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        model.$revision.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &bag)
        model.collector.$authorization.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &bag)
        model.collector.$mode.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &bag)
        // fixes arrive every few seconds while moving and bump nothing above; refresh "last point" at most every
        // 10 min so the tracking widgets don't go stale mid-trip without spending the reload budget
        model.collector.$lastFix.dropFirst()
            .throttle(for: .seconds(600), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.schedule() }.store(in: &bag)
    }

    func schedule(after delay: Duration = .seconds(2)) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    func publish() {
        pending?.cancel()
        guard let model, let url = Self.snapshotURL else { return }
        do {
            let snap = try WidgetSnapshot.build(store: model.store, tracking: tracking(model.collector),
                                                diaryUpdatedAt: model.engine.lastRunAt, usesMetric: Fmt.usesMetric)
            let previous = last ?? WidgetSnapshot.read(from: url)
            // rewrite at least hourly so the widget's "updated" time stays honest
            if let previous, previous.sameContent(as: snap), snap.generatedAt.timeIntervalSince(previous.generatedAt) < 3600 {
                return
            }
            try snap.write(to: url)
            last = snap
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            NSLog("HHT: widget snapshot failed \(error)")
        }
    }

    private func tracking(_ c: LocationCollector) -> WidgetSnapshot.Tracking {
        guard c.isEnabled else { return .paused }
        switch c.authorization {
        case .authorizedAlways: return .recording
        #if os(iOS)
        case .authorizedWhenInUse: return .backgroundLimited
        #endif
        default: return .permissionNeeded
        }
    }
}

/// Where a widget tap lands (`hht://<route>`). `stamp` opens Today and stamps, exactly like its button.
enum AppRoute: String {
    case today, stats, settings, stamp
}
