import SwiftUI
import UniformTypeIdentifiers
import HHTCore
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var collector = AppModel.shared.collector
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reverseGeocoding") private var reverseGeocoding = false
    @AppStorage("collectorProfile") private var profile = LocationCollector.Profile.balanced.rawValue
    @AppStorage("units") private var units = ""
    @AppStorage("agentEnabled") private var agentEnabled = false

    @State private var counts: [String: Int] = [:]
    @State private var exportRange = 0          // 0 all, 1 last 30 days
    @State private var includeRaw = true
    @State private var exportedFiles: [URL] = []
    @State private var exportFolder: URL?
    @State private var busy = false
    @State private var importKind: ImportKind?
    @State private var message: String?
    @State private var confirmErase = false
    @State private var confirmErase2 = false
    @State private var confirmAirports = false
    @State private var airportCount = 0

    enum ImportKind: String, Identifiable { case trips, flights, gpx; var id: String { rawValue } }

    var body: some View {
        Form {
            collectionSection
            privacySection
            exportSection
            importSection
            maintenanceSection
            Section {
                Picker("Units", selection: $units) {
                    Text("System").tag(""); Text("Metric").tag("metric"); Text("Imperial").tag("imperial")
                }
            } header: { Text("Display").toonSectionText() }
            Section {
                Toggle("Diary agent", isOn: $agentEnabled)
            } header: { Text("Experimental").toonSectionText() } footer: {
                Text("Adds an Agent tab that recaps your day, asks about stops it can't explain, suggests mode fixes and answers simple questions. It runs on this iPhone with fixed rules: no AI model, nothing is sent anywhere. Off by default.")
                    .toonSectionText()
            }
            aboutSection
        }
        .toonBackground()
        .navigationTitle("Settings")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.confirmTint() } }
        .task(id: model.revision) {
            counts = model.store.counts()
            airportCount = Importer(store: model.store).airportCount()
        }
        .fileImporter(isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
                      allowedContentTypes: importKind == .gpx ? [UTType(filenameExtension: "gpx") ?? .xml, .xml] : [.commaSeparatedText, .plainText]) { result in
            let kind = importKind
            importKind = nil
            if case .success(let url) = result, let kind { runImport(kind, url) }
        }
        .alert("Done", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    // MARK: sections

    private var collectionSection: some View {
        Section {
            Toggle("Record location", isOn: Binding(
                get: { collector.mode != .off },
                set: { $0 ? collector.start() : collector.stop() }))
            LabeledContent("Permission", value: collector.authorizationLabel)
            LabeledContent("Collector state", value: collector.mode.rawValue)
            if let f = collector.lastFix { LabeledContent("Last fix", value: Fmt.dateTime(f)) }
            LabeledContent("Motion activity", value: MotionSync.isAvailable ? "available" : "unavailable")
            Picker("Accuracy", selection: $profile) {
                ForEach(LocationCollector.Profile.allCases) { p in Text(p.label).tag(p.rawValue) }
            }
            .onChange(of: profile) { _, v in collector.profile = LocationCollector.Profile(rawValue: v) ?? .balanced }
            #if os(iOS)
            if collector.authorization != .authorizedAlways {
                Button("Open iOS Settings to allow “Always”") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            #endif
        } header: { Text("Collection").toonSectionText() } footer: {
            Text("GPS runs only while you're moving. When you stop for ~3 min it switches off and a geofence, iOS visit detection and significant-change monitoring wake the app when you leave — even after it was closed.")
                .toonSectionText()
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Look up addresses (Apple)", isOn: $reverseGeocoding)
                .onChange(of: reverseGeocoding) { _, on in if on { model.geocoder.backfill() } }
        } header: { Text("Privacy").toonSectionText() } footer: {
            Text("Everything is stored only on this iPhone. Address lookup is the only feature that sends coordinates anywhere (to Apple's geocoder, one place at a time) and is off by default. Map tiles are loaded from Apple Maps.")
                .toonSectionText()
        }
    }

    private var exportSection: some View {
        Section {
            Picker("Range", selection: $exportRange) { Text("Everything").tag(0); Text("Last 30 days").tag(1) }
            Toggle("Include raw GPS points", isOn: $includeRaw)
            Button {
                export()
            } label: {
                HStack { Label("Create export", systemImage: "square.and.arrow.up.on.square"); if busy { Spacer(); ProgressView() } }
            }
            .disabled(busy)
            if !exportedFiles.isEmpty {
                ShareLink(items: exportedFiles) { Label("Share \(exportedFiles.count) files…", systemImage: "square.and.arrow.up") }
                if let folder = exportFolder {
                    Text("Also saved in Files › On My iPhone › TripLibre › Exports › \(folder.lastPathComponent)").font(.caption).foregroundStyle(Toon.muted)
                }
            }
        } header: { Text("Export for analysis").toonSectionText() } footer: {
            Text("CSV (trips, segments, visits, places, flights…), full JSON, GeoJSON and a SQLite snapshot. Stable IDs join across tables. See analysis/ in the repo for Python helpers.")
                .toonSectionText()
        }
    }

    private var importSection: some View {
        Section {
            Button { importKind = .trips } label: { Label("Import past trips (CSV)", systemImage: "tablecells") }
            Button { importKind = .flights } label: { Label("Import flights (CSV)", systemImage: "airplane") }
            Button { importKind = .gpx } label: { Label("Import GPX track", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            if airportCount > 0 {
                LabeledContent("Airport list", value: "\(airportCount) airports")
            } else {
                Button { confirmAirports = true } label: { Label("Download airport list (OurAirports)", systemImage: "arrow.down.circle") }
            }
        } header: { Text("Import").toonSectionText() } footer: {
            Text("Trips CSV: date,start_time,end_time,origin,destination,mode,distance_km,purpose,notes. Flights CSV: date,origin,destination,airline,flight_number,… Formats are in docs/import-formats.md.")
                .toonSectionText()
        }
        .confirmationDialog("Download ~12 MB public-domain airport list from ourairports.com?", isPresented: $confirmAirports, titleVisibility: .visible) {
            Button("Download") { downloadAirports() }
        } message: { Text("Only the list is downloaded; nothing about you is sent.") }
    }

    private var maintenanceSection: some View {
        Section {
            Button("Rebuild last 7 days from raw data") {
                Task { await model.reprocess(from: Date().addingTimeInterval(-7 * 86_400), to: Date()); message = rebuildMessage }
            }
            Button("Rebuild everything from raw data") {
                Task { await model.reprocess(from: .distantPast, to: Date()); message = rebuildMessage }
            }
            Button("Back up database now") {
                do { let u = try model.backupNow(); message = "Saved \(u.lastPathComponent) in Files › TripLibre › Backups" } catch { message = "\(error)" }
            }
            #if targetEnvironment(simulator)
            Button("Load demo data (simulator only)") {
                model.perform { try DemoData.generate(into: model.store) }
                Task { await model.reprocess(from: .distantPast, to: Date()) }
            }
            #endif
            Button("Erase all data…", role: .destructive) { confirmErase = true }
        } header: { Text("Data").toonSectionText() } footer: {
            Text("Rebuilding re-runs detection on raw points; anything you corrected, confirmed, deleted or created stays as it is. A database snapshot is also saved daily (last 7 kept).")
                .toonSectionText()
        }
        .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase all location history", role: .destructive) { confirmErase2 = true }
        } message: { Text("Raw points, visits, trips, places, flights and edits will be permanently deleted from this iPhone. Backups in Files are not touched.") }
        .alert("Really erase?", isPresented: $confirmErase2) {
            Button("Erase", role: .destructive) { model.perform { try model.store.eraseAll() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var aboutSection: some View {
        Section {
            ForEach(["raw_location_points", "motion_activities", "visits", "trips", "trip_segments", "places", "flights", "audit_log"], id: \.self) { k in
                LabeledContent(k, value: "\(counts[k] ?? 0)")
            }
            LabeledContent("Schema version", value: "\(model.store.schemaVersion)")
            LabeledContent("Last diary update") {
                if model.isProcessing { Text("Running now…") }
                else if let d = model.lastInferenceAt { Text(d, format: .relative(presentation: .named)) }
                else { Text("Never") }
            }
            LabeledContent("Stay radius / min dwell", value: "\(Int(model.engine.config.stayRadius)) m / \(Int(model.engine.config.minStayDuration / 60)) min")
        } header: { Text("Database").toonSectionText() }
    }

    // MARK: actions

    private var rebuildMessage: String {
        if model.isProcessing { return "Queued; it runs as soon as the update in progress finishes." }
        if let f = model.inferenceFailure { return "Rebuild failed: \(f.message)" }
        return "Rebuilt. Your edits were kept."
    }

    private func export() {
        busy = true
        defer { busy = false }
        do {
            var opts = Exporter.Options(range: exportRange == 1 ? .lastDays(30) : nil)
            opts.includeRawPoints = includeRaw
            let folder = try Exporter(store: model.store).exportBundle(to: AppModel.exportsDirectory, options: opts)
            exportFolder = folder
            exportedFiles = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            model.errorMessage = "Export failed: \(error)"
        }
    }

    private func runImport(_ kind: ImportKind, _ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let imp = Importer(store: model.store)
        do {
            switch kind {
            case .trips, .flights:
                let text = try String(contentsOf: url, encoding: .utf8)
                let r = kind == .trips ? try imp.importTrips(csv: text) : try imp.importFlights(csv: text)
                message = "Imported \(r.imported), skipped \(r.skipped)." + (r.messages.isEmpty ? "" : "\n" + r.messages.prefix(5).joined(separator: "\n"))
                model.touch()
            case .gpx:
                let r = try imp.importGPX(Data(contentsOf: url))
                if let s = r.start, let e = r.end {
                    Task { await model.reprocess(from: s, to: e) }
                }
                message = "Imported \(r.count) GPS points; visits and trips are being reconstructed."
            }
        } catch {
            model.errorMessage = "Import failed: \(error)"
        }
    }

    private func downloadAirports() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: Importer.ourAirportsURL)
                let n = try Importer(store: model.store).importAirports(csv: String(decoding: data, as: UTF8.self))
                airportCount = n
                message = "Loaded \(n) airports."
            } catch {
                model.errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}
