import Foundation
import SwiftUI
import HHTCore

/// Owns the database and services; views observe `revision` to reload after any change.
@MainActor
final class AppModel: ObservableObject {
    /// One instance per process: shared by the SwiftUI scene and the app delegate (background relaunches).
    static let shared = AppModel()

    let store: TravelStore
    let engine: InferenceEngine
    let edit: EditService
    let collector: LocationCollector
    let motion: MotionSync
    let geocoder: PlaceGeocoder

    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    @Published private(set) var isProcessing = false
    /// A screen a widget tap asked for; the root view consumes it.
    @Published var route: AppRoute?
    private(set) var widgets: WidgetBridge!

    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HHT", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Visible in the Files app (On My iPhone › HHT) because UIFileSharingEnabled is set.
    static var documentsDirectory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var exportsDirectory: URL { documentsDirectory.appendingPathComponent("Exports", isDirectory: true) }
    static var backupsDirectory: URL { documentsDirectory.appendingPathComponent("Backups", isDirectory: true) }

    /// Launch argument `-hhtUITest YES` (simulator builds only, issue #64): UI tests get a fresh throwaway database
    /// seeded with demo data, and no location collection or backups touch the real one.
    static var isUITest: Bool {
        #if targetEnvironment(simulator)
        UserDefaults.standard.bool(forKey: "hhtUITest")
        #else
        false
        #endif
    }

    private static func freshUITestDatabase() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hht-uitest.sqlite")
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        return url
    }

    init() {
        let path = Self.isUITest ? Self.freshUITestDatabase() : Self.supportDirectory.appendingPathComponent("travel.sqlite")
        do {
            store = try TravelStore(path: path.path)
        } catch {
            fatalError("Cannot open database at \(path.path): \(error)")
        }
        engine = InferenceEngine(store: store)
        edit = EditService(store: store)
        collector = LocationCollector(store: store)
        motion = MotionSync(store: store)
        geocoder = PlaceGeocoder(store: store)
        engine.onPlaceCreated = { [weak self] p in
            Task { @MainActor in self?.geocoder.enqueue(p.id) }
        }
        collector.profile = LocationCollector.Profile(rawValue: UserDefaults.standard.string(forKey: "collectorProfile") ?? "") ?? .balanced
        collector.onStationary = { [weak self] in
            Task { @MainActor in await self?.runInference() }
        }
        widgets = WidgetBridge(model: self)
    }

    private var launched = false

    /// Safe to call repeatedly (delegate launch, scene appear).
    func launch() {
        guard !launched else { return }
        launched = true
        if !Self.isUITest { collector.resumeIfEnabled() }
        #if targetEnvironment(simulator)
        // launch argument `-hhtDemo YES` seeds demo data (simulator builds only)
        if UserDefaults.standard.bool(forKey: "hhtDemo") || Self.isUITest, store.pointCount() == 0 {
            UserDefaults.standard.set(true, forKey: "onboarded")
            try? DemoData.generate(into: store)
        }
        #endif
        refreshInferenceStatus()
        widgets.schedule()
        Task { await runInference() }
        autoBackupIfDue()
    }

    // MARK: - Inference

    /// What a run is doing right now; `syncingMotion` happens before the engine starts.
    enum InferencePhase: Equatable {
        case syncingMotion
        case engine(InferenceEngine.Phase)
    }

    struct InferenceFailure: Equatable {
        var message: String
        var at: Date
    }

    @Published private(set) var phase: InferencePhase?
    @Published private(set) var progress: InferenceEngine.Progress?
    @Published private(set) var runStartedAt: Date?
    /// Another trigger arrived mid-run; it will run once the current one commits.
    @Published private(set) var rerunRequested = false
    /// The last run failed (its transaction rolled back); cleared by the next successful run.
    @Published private(set) var inferenceFailure: InferenceFailure?
    @Published private(set) var lastInferenceAt: Date?
    /// Raw data newer than the diary's last stop that no run has resolved yet.
    @Published private(set) var pendingTail: InferenceEngine.UnresolvedTail?

    /// Sync motion history, then reconstruct visits/trips from new observations.
    /// Triggers that arrive mid-run are coalesced into one more run instead of being dropped.
    func runInference() async {
        rerunRequested = true
        guard !isProcessing else { return }
        await withRun {
            while rerunRequested {
                rerunRequested = false
                if let r = queuedRange {
                    queuedRange = nil
                    await runEngine { try $0.process(from: r.from, to: r.to) }
                } else {
                    await runEngine { try $0.processNew() }
                }
            }
        }
    }

    /// Reprocess a range from raw data (user edits are kept). Queued behind a run already in progress.
    func reprocess(from: Date, to: Date) async {
        queuedRange = queuedRange.map { (min($0.from, from), max($0.to, to)) } ?? (from, to)
        await runInference()
    }

    private var queuedRange: (from: Date, to: Date)?

    /// Re-check how much raw data is waiting to be resolved (cheap; safe to call often).
    func refreshInferenceStatus() {
        lastInferenceAt = engine.lastRunAt
        pendingTail = try? engine.unresolvedTail()
    }

    private func withRun(_ body: () async -> Void) async {
        isProcessing = true
        runStartedAt = Date()
        defer {
            isProcessing = false
            runStartedAt = nil
            phase = nil
            progress = nil
            refreshInferenceStatus()
        }
        await body()
    }

    /// Motion sync, then the engine on a background thread so the diary stays usable while it runs.
    private func runEngine(_ work: @escaping (InferenceEngine) throws -> InferenceEngine.Report) async {
        phase = .syncingMotion
        progress = nil
        await motion.sync()
        let engine = self.engine
        engine.onProgress = { p in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isProcessing else { return }
                self.progress = p
                self.phase = .engine(p.phase)
            }
        }
        defer { engine.onProgress = nil }
        do {
            _ = try await Task.detached(priority: .utility) { try work(engine) }.value
            inferenceFailure = nil
        } catch {
            inferenceFailure = InferenceFailure(message: "\(error)", at: Date())
        }
        revision += 1
    }

    // MARK: - Stamps

    /// The stamp just made, for the "Stamped · Undo" confirmation.
    @Published private(set) var lastStamp: Stamp?
    /// The last tap repeated a stamp made seconds earlier, so nothing new was saved.
    @Published private(set) var lastStampRepeated = false

    /// One tap: record that something worth noting happened around here, around now (issue #32).
    /// Saves immediately with whatever fix is at hand (only a coarse location is kept), then lets inference place it.
    /// The Today button and the Stamp widget (`hht://stamp`, issue #47) both come here; a repeat within
    /// `EditService.stampRepeatWindow` shows the stamp already saved instead of adding another.
    func stampNow() {
        let now = Date()
        var fix = collector.latestLocation.flatMap { $0.horizontalAccuracy >= 0 ? $0 : nil }
            .map { (Coordinate($0.coordinate.latitude, $0.coordinate.longitude), $0.horizontalAccuracy, $0.timestamp) }
        if fix == nil, let p = store.lastPoint() { fix = (p.coordinate, p.horizontalAccuracy ?? 100, p.timestamp) }
        do {
            let r = try edit.stampOnce(at: now, fix: fix?.0, fixAccuracy: fix?.1, fixTime: fix?.2)
            lastStamp = r.stamp
            lastStampRepeated = !r.isNew
            guard r.isNew else { return }
        } catch {
            errorMessage = "Couldn't save the stamp: \(error)"
            return
        }
        revision += 1
        collector.noteStamp()
        Task { await reprocess(from: now.addingTimeInterval(-engine.config.stampSearchWindow), to: now) }
    }

    func undoStamp(_ s: Stamp) {
        if lastStamp?.id == s.id { lastStamp = nil }
        perform { try edit.deleteStamp(s.id) }
        Task { await reprocess(from: s.timestamp.addingTimeInterval(-engine.config.stampSearchWindow), to: Date()) }
    }

    func dismissStampConfirmation() { lastStamp = nil }

    /// Run an edit; report errors; refresh views.
    func perform(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        revision += 1
    }

    func touch() { revision += 1 }

    // MARK: - Backups

    /// Daily SQLite snapshot into Documents/Backups (keeps the last 7). Never deletes anything else.
    func autoBackupIfDue() {
        guard !Self.isUITest else { return }
        let key = "lastAutoBackup"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400, store.pointCount() > 0 else { return }
        do {
            try backupNow()
            UserDefaults.standard.set(Date(), forKey: key)
        } catch {
            NSLog("HHT: backup failed \(error)")
        }
    }

    @discardableResult
    func backupNow() throws -> URL {
        let dir = Self.backupsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("travel-\(f.string(from: Date())).sqlite")
        try store.backup(to: url)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let snapshots = files.filter { $0.lastPathComponent.hasPrefix("travel-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in snapshots.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
        return url
    }
}
