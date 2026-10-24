import SwiftUI
import MapKit
import HHTCore

struct VisitDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let visitID: String

    @State private var visit: Visit?
    @State private var place: Place?
    @State private var arrival = Date()
    @State private var departure = Date()
    @State private var ongoing = false
    @State private var notes = ""
    @State private var history: [AuditEntry] = []
    @State private var stamps: [Stamp] = []
    @State private var costs: [Expense] = []
    @State private var costSheet: CostSheet?
    @State private var showPlacePicker = false
    @State private var showSplit = false
    @State private var confirmDelete = false
    @State private var editPlace: IDBox?

    var body: some View {
        NavigationStack {
            Group {
                if let v = visit { content(v) } else { ProgressView() }
            }
            .toonBackground()
            .navigationTitle("Visit")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveNotes(); dismiss() }.confirmTint() } }
            .task(id: model.revision) { load() }
        }
    }

    @ViewBuilder private func content(_ v: Visit) -> some View {
        Form {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(center: v.coordinate.cl, latitudinalMeters: 600, longitudinalMeters: 600))) {
                    if let p = place {
                        MapCircle(center: p.coordinate.cl, radius: p.radius).foregroundStyle(.blue.opacity(0.15)).stroke(.blue, lineWidth: 1)
                    }
                    Marker(place?.displayName ?? "Visit", coordinate: v.coordinate.cl)
                }
                .mapStyle(.standard(pointsOfInterest: .including([.restaurant, .cafe, .university, .airport, .publicTransport, .store, .hospital, .park])))
                .frame(height: 200).listRowInsets(EdgeInsets())
            }

            Section {
                HStack {
                    Image(systemName: place?.category?.symbol ?? "mappin")
                    VStack(alignment: .leading) {
                        Text(place?.isNamed == true ? place!.displayName : "Unnamed place").font(.headline)
                        if let a = place?.address { Text(a).font(.caption).foregroundStyle(Toon.muted) }
                    }
                }
                Button { showPlacePicker = true } label: { Label("Wrong place? Choose or create…", systemImage: "arrow.triangle.swap") }
                if let p = place {
                    Button { editPlace = IDBox(id: p.id) } label: {
                        Label(p.isNamed ? "Edit “\(p.displayName)” (all visits)" : "Name this place", systemImage: "pencil")
                    }
                }
            } header: { Text("Place").toonSectionText() }

            Section {
                Picker("Activity", selection: Binding(
                    get: { v.purpose },
                    set: { p in model.perform { try model.edit.setVisitPurpose(v.id, p) } })) {
                    Text(place?.category?.defaultPurpose.map { "Auto (\($0.label))" } ?? "Not set").tag(TripPurpose?.none)
                    ForEach(TripPurpose.allCases) { p in Text(p.label).tag(TripPurpose?.some(p)) }
                }
            } header: { Text("Purpose").toonSectionText() }

            Section {
                DatePicker("Arrived", selection: $arrival)
                Toggle("Still here", isOn: $ongoing)
                if !ongoing { DatePicker("Left", selection: $departure, in: arrival...) }
                if timesChanged(v) {
                    Button("Save times") {
                        model.perform { try model.edit.setVisitTimes(v.id, arrival: arrival, departure: ongoing ? nil : departure) }
                    }
                }
                Text(Fmt.duration((ongoing ? Date() : departure).timeIntervalSince(arrival))).foregroundStyle(Toon.muted)
            } header: { Text("Time").toonSectionText() }

            if !stamps.isEmpty {
                Section {
                    ForEach(stamps) { s in
                        HStack {
                            Label("You stamped at \(Fmt.time(s.timestamp, tz: s.timeZone))", systemImage: StampStyle.symbol)
                            Spacer()
                            if s.coordinate != nil, let u = s.uncertainty {
                                Text("±\(Fmt.distance(u))").font(.caption).foregroundStyle(Toon.muted)
                            }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { model.undoStamp(s) } }
                    }
                } header: {
                    Text("Self-reported")
                        .toonSectionText()
                } footer: {
                    Text(v.pointCount == 0
                         ? "This stop comes from your stamp alone; there was no GPS around it."
                         : "Your stamp confirms this stop. Its place and times still come from GPS, not from where you tapped.")
                        .toonSectionText()
                }
            }

            CostsSection(costs: costs, target: .visit(v, place), sheet: $costSheet)

            Section {
                TextField("Add a note", text: $notes, axis: .vertical).onSubmit(saveNotes)
            } header: { Text("Notes").toonSectionText() }

            Section {
                if v.userStatus == .auto {
                    Button { model.perform { try model.edit.confirm(visitID: v.id) } } label: {
                        Label("Looks right", systemImage: "checkmark.circle")
                    }
                }
                Button { showSplit = true } label: { Label("I left and came back / add a missing stop", systemImage: "arrow.uturn.right") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("This wasn't a stop", systemImage: "trash") }
            }

            Section {
                LabeledContent("Status", value: v.userStatus.rawValue)
                LabeledContent("Source", value: v.source.rawValue)
                if let c = v.autoConfidence { LabeledContent("Confidence", value: Fmt.percent(c)) }
                if let n = v.pointCount { LabeledContent("GPS fixes", value: "\(n)") }
                LabeledContent("Visit ID", value: String(v.id.prefix(8)))
                if !history.isEmpty {
                    DisclosureGroup("Edit history (\(history.count))") {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                            Text("\(h.action) \(h.field ?? ""): \(h.oldValue ?? "∅") → \(h.newValue ?? "∅")").font(.caption2)
                        }
                    }
                }
            } header: { Text("Details").toonSectionText() }
        }
        .confirmationDialog("Remove this visit?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove and join the trips before/after", role: .destructive) {
                model.perform { try model.edit.deleteVisit(v.id) }
                dismiss()
            }
        } message: { Text("Use this for traffic lights, transfers or GPS noise that looked like a stop.") }
        .sheet(isPresented: $showPlacePicker) {
            PlacePickerView(near: v.coordinate) { choice in
                switch choice {
                case .existing(let id): model.perform { try model.edit.setVisitPlace(v.id, placeID: id) }
                case .new(let name, let cat, let custom):
                    model.perform { try model.edit.createPlace(forVisit: v.id, name: name, category: cat, customCategory: custom) }
                }
            }
            .environmentObject(model)
        }
        .sheet(item: $editPlace) { box in NavigationStack { PlaceDetailView(placeID: box.id) }.environmentObject(model) }
        .sheet(item: $costSheet) { c in CostEntrySheet(target: c.target, existing: c.existing).environmentObject(model) }
        .sheet(isPresented: $showSplit) { SplitVisitSheet(visit: v).environmentObject(model) }
    }

    private func timesChanged(_ v: Visit) -> Bool {
        abs(arrival.timeIntervalSince(v.arrival)) > 30 || ongoing != (v.departure == nil)
            || (!ongoing && abs(departure.timeIntervalSince(v.departure ?? departure)) > 30)
    }

    private func saveNotes() {
        guard let v = visit, notes != (v.notes ?? "") else { return }
        model.perform { try model.edit.setNotes(visitID: v.id, notes) }
    }

    private func load() {
        guard let v = try? model.store.visit(visitID) else { visit = nil; return }
        visit = v
        place = v.placeID.flatMap { try? model.store.place($0) }
        arrival = v.arrival
        departure = v.departure ?? Date()
        ongoing = v.departure == nil
        notes = v.notes ?? ""
        history = (try? model.store.auditLog(entityID: v.id)) ?? []
        stamps = (try? model.store.stamps(visitID: v.id)) ?? []
        costs = (try? model.store.expenses(visitID: v.id)) ?? []
    }
}

enum PlaceChoice { case existing(String), new(String, PlaceCategory?, String?) }

struct PlacePickerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let near: Coordinate
    var onPick: (PlaceChoice) -> Void

    @State private var query = ""
    @State private var places: [Place] = []
    @State private var newName = ""
    @State private var newCategory: PlaceCategory? = nil
    @State private var newCustom: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name (e.g. Home, Penn, 30th St Station)", text: $newName)
                    PlaceCategoryPicker(selection: $newCategory, custom: $newCustom)
                    Button("Create and use") {
                        onPick(.new(newName.trimmingCharacters(in: .whitespaces), newCategory, newCustom))
                        dismiss()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("New place here").toonSectionText() }
                Section(query.isEmpty ? "Nearby" : "Matches") {
                    ForEach(filtered) { p in
                        Button {
                            onPick(.existing(p.id))
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: p.category?.symbol ?? "mappin").frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(p.displayName).foregroundStyle(.primary)
                                    Text(Fmt.distance(Geo.distance(p.coordinate, near)) + " away").font(.caption).foregroundStyle(Toon.muted)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search your places")
            .navigationTitle("Choose place")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                places = ((try? model.store.places()) ?? []).sorted { Geo.distance($0.coordinate, near) < Geo.distance($1.coordinate, near) }
            }
        }
    }

    private var filtered: [Place] {
        if query.isEmpty { return Array(places.filter { $0.isNamed || Geo.distance($0.coordinate, near) < 1000 }.prefix(30)) }
        return places.filter { $0.displayName.localizedCaseInsensitiveContains(query) || ($0.code ?? "").localizedCaseInsensitiveContains(query) }
    }
}

/// "I left and came back", optionally via a stop somewhere.
struct SplitVisitSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    // Seeded in init, not onAppear: the picker ranges below are built on first render and trap if inverted.
    @State private var leave: Date
    @State private var back: Date
    @State private var withStop = false
    @State private var stopPlaceID: String?
    @State private var stopArrive: Date
    @State private var stopLeave: Date
    @State private var mode: TravelMode = .walk
    @State private var places: [Place] = []
    private let upper: Date

    init(visit: Visit) {
        self.visit = visit
        upper = max(visit.arrival, visit.departure ?? Date())
        let t = SplitTimes.visit(arrival: visit.arrival, departure: visit.departure)
        _leave = State(initialValue: t.leave)
        _back = State(initialValue: t.back)
        _stopArrive = State(initialValue: t.stopArrival)
        _stopLeave = State(initialValue: t.stopDeparture)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Left", selection: $leave, in: .ordered(visit.arrival, upper))
                    DatePicker("Came back", selection: $back, in: .ordered(leave, upper))
                    Picker("Mode", selection: $mode) {
                        ForEach(TravelMode.allCases) { m in Label(m.label, systemImage: m.symbol).tag(m) }
                    }
                }
                Section {
                    Toggle("I went somewhere specific", isOn: $withStop)
                    if withStop {
                        Picker("Place", selection: $stopPlaceID) {
                            Text("Choose…").tag(String?.none)
                            ForEach(places) { p in Text(p.displayName).tag(String?.some(p.id)) }
                        }
                        DatePicker("Arrived there", selection: $stopArrive, in: .ordered(leave, back))
                        DatePicker("Left there", selection: $stopLeave, in: .ordered(stopArrive, back))
                    }
                } footer: {
                    Text("Creates the missing trip(s). Places must exist already — create one from any visit or in Places.")
                        .toonSectionText()
                }
            }
            .navigationTitle("Split visit")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.perform {
                            let stop = withStop ? stopPlaceID.map { (placeID: $0, arrival: stopArrive, departure: stopLeave) } : nil
                            try model.edit.splitVisit(visit.id, leave: leave, back: back, stop: stop, mode: mode)
                        }
                        dismiss()
                    }
                    .disabled(withStop && stopPlaceID == nil)
                    .confirmTint()
                }
            }
            // Keep leave ≤ stop arrival ≤ stop departure ≤ back as the user drags earlier times later.
            .onChange(of: leave) { _, v in back = max(back, v); stopArrive = max(stopArrive, v) }
            .onChange(of: back) { _, v in stopLeave = min(stopLeave, v); stopArrive = min(stopArrive, v) }
            .onChange(of: stopArrive) { _, v in stopLeave = max(stopLeave, v) }
            .onAppear {
                places = ((try? model.store.places()) ?? []).filter(\.isNamed)
            }
        }
    }
}
