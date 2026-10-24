import SwiftUI
import MapKit
import HHTCore

struct FlightsView: View {
    @EnvironmentObject var model: AppModel
    @State private var flights: [Flight] = []
    @State private var editing: Flight?
    @State private var adding = false

    var body: some View {
        List {
            let s = Analytics.flightStats(flights)
            Section {
                Map(initialPosition: .automatic) {
                    ForEach(flights) { f in
                        if let o = f.origin, let d = f.destination {
                            MapPolyline(MKGeodesicPolyline(coordinates: [o.cl, d.cl], count: 2)).stroke(.purple, lineWidth: 2)
                        }
                    }
                }
                .frame(height: 220).listRowInsets(EdgeInsets())
                HStack {
                    StatPill(value: "\(s.flights)", label: "flights")
                    StatPill(value: Fmt.distance(s.distance), label: "distance")
                    StatPill(value: "\(s.airports.count)", label: "airports")
                    StatPill(value: "\(s.routes.count)", label: "routes")
                }
            }
            if !s.airports.isEmpty {
                Section {
                    ForEach(s.airports.sorted { $0.value > $1.value }.prefix(10), id: \.key) { k, v in
                        LabeledContent(k, value: "\(v)")
                    }
                } header: { Text("Airports").toonSectionText() }
            }
            Section {
                ForEach(flights) { f in
                    Button { editing = f } label: {
                        VStack(alignment: .leading) {
                            Text(f.routeLabel).font(.headline).foregroundStyle(.primary)
                            Text([f.date, f.airline, f.flightNumber, f.effectiveDistance.map(Fmt.distance)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Toon.muted)
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { model.perform { try model.store.deleteFlight(flights[i].id) } }
                }
            } header: { Text("All flights").toonSectionText() }
        }
        .toonBackground()
        .navigationTitle("Flights")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add flight") } }
        .sheet(isPresented: $adding) { FlightEditor(flight: nil).environmentObject(model) }
        .sheet(item: $editing) { f in FlightEditor(flight: f).environmentObject(model) }
        .task(id: model.revision) { flights = (try? model.store.flights()) ?? [] }
    }
}

struct FlightEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let flight: Flight?
    @State private var date = Date()
    @State private var origin = ""
    @State private var destination = ""
    @State private var airline = ""
    @State private var number = ""
    @State private var aircraft = ""
    @State private var seat = ""
    @State private var notes = ""
    @State private var lookupNote = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("From (IATA, e.g. PHL)", text: $origin).capsKeyboard()
                TextField("To (IATA, e.g. SLC)", text: $destination).capsKeyboard()
                TextField("Airline", text: $airline)
                TextField("Flight number", text: $number)
                TextField("Aircraft", text: $aircraft)
                TextField("Seat", text: $seat)
                TextField("Notes", text: $notes, axis: .vertical)
                if !lookupNote.isEmpty { Text(lookupNote).font(.caption).foregroundStyle(Toon.muted) }
            }
            .navigationTitle(flight == nil ? "Add flight" : "Edit flight")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(origin.count < 3 || destination.count < 3).confirmTint() }
            }
            .onAppear {
                guard let f = flight else { return }
                date = Fmt.parseYMD(f.date) ?? Date()
                origin = f.originCode ?? ""; destination = f.destinationCode ?? ""
                airline = f.airline ?? ""; number = f.flightNumber ?? ""; aircraft = f.aircraftType ?? ""
                seat = f.seat ?? ""; notes = f.notes ?? ""
            }
        }
    }

    private func save() {
        let imp = Importer(store: model.store)
        let o = origin.uppercased().trimmingCharacters(in: .whitespaces), d = destination.uppercased().trimmingCharacters(in: .whitespaces)
        var f = flight ?? Flight(date: Fmt.ymd(date))
        f.date = Fmt.ymd(date)
        f.originCode = o; f.destinationCode = d
        f.origin = imp.airport(o)?.coordinate ?? f.origin
        f.destination = imp.airport(d)?.coordinate ?? f.destination
        f.distance = nil
        f.airline = airline.isEmpty ? nil : airline
        f.flightNumber = number.isEmpty ? nil : number
        f.aircraftType = aircraft.isEmpty ? nil : aircraft
        f.seat = seat.isEmpty ? nil : seat
        f.notes = notes.isEmpty ? nil : notes
        f.updatedAt = Date()
        if f.origin == nil || f.destination == nil, imp.airportCount() == 0 {
            lookupNote = "Saved without coordinates. Download the airport list in Settings to get distances and map routes."
        }
        model.perform { try model.store.upsertFlight(f); _ = try imp.airportPlace(o); _ = try imp.airportPlace(d) }
        dismiss()
    }
}

struct LifePhasesView: View {
    @EnvironmentObject var model: AppModel
    @State private var phases: [LifePhase] = []
    @State private var editing: LifePhase?

    var body: some View {
        List {
            Section {
                ForEach(phases) { p in
                    Button { editing = p } label: {
                        VStack(alignment: .leading) {
                            Text(p.name).foregroundStyle(.primary)
                            Text("\(p.startDate) – \(p.endDate ?? "now")" + (p.kind.map { " · \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(Toon.muted)
                        }
                    }
                }
                .onDelete { idx in for i in idx { model.perform { try model.store.deleteLifePhase(phases[i].id) } } }
            } footer: {
                Text("Periods like a semester, a job or a city of residence. Stats can be computed and compared per phase.")
                    .toonSectionText()
            }
        }
        .toonBackground()
        .navigationTitle("Life phases")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = LifePhase(name: "", startDate: Fmt.ymd(Date())) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add life phase")
            }
        }
        .sheet(item: $editing) { p in PhaseEditor(phase: p).environmentObject(model) }
        .task(id: model.revision) { phases = (try? model.store.lifePhases()) ?? [] }
    }
}

struct PhaseEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var phase: LifePhase
    @State private var start = Date()
    @State private var end = Date()
    @State private var ongoing = true
    static let kinds = ["semester", "job", "residence", "vacation", "research_trip", "other"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Fall 2026, PhD Year 1)", text: $phase.name)
                Picker("Kind", selection: Binding(get: { phase.kind }, set: { phase.kind = $0 })) {
                    Text("–").tag(String?.none)
                    ForEach(Self.kinds, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag(String?.some($0)) }
                }
                DatePicker("Start", selection: $start, displayedComponents: .date)
                Toggle("Ongoing", isOn: $ongoing)
                if !ongoing { DatePicker("End", selection: $end, in: start..., displayedComponents: .date) }
                TextField("Notes", text: Binding(get: { phase.notes ?? "" }, set: { phase.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
            }
            .navigationTitle("Life phase")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        phase.startDate = Fmt.ymd(start)
                        phase.endDate = ongoing ? nil : Fmt.ymd(end)
                        model.perform { try model.store.upsertLifePhase(phase) }
                        dismiss()
                    }
                    .disabled(phase.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .confirmTint()
                }
            }
            .onAppear {
                start = Fmt.parseYMD(phase.startDate) ?? Date()
                ongoing = phase.endDate == nil
                end = phase.endDate.flatMap(Fmt.parseYMD) ?? Date()
            }
        }
    }
}

/// Trips flagged as uncertain, newest first — quick one-tap corrections.
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @State private var trips: [Trip] = []
    @State private var quick: [TravelMode] = [.walk, .bus, .subway, .car]
    @State private var selected: IDBox?

    var body: some View {
        List {
            if trips.isEmpty { Text("All caught up.").foregroundStyle(Toon.muted) }
            ForEach(trips) { t in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.shortDay(t.departure)).font(.caption.weight(.semibold)).foregroundStyle(Toon.muted)
                    TripRow(trip: t, quickModes: quick, day: t.departure) { m in
                        model.perform { try model.edit.setTripMode(t.id, m) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selected = IDBox(id: t.id) }
            }
        }
        .toonBackground()
        .navigationTitle("To check")
        .sheet(item: $selected) { b in TripDetailView(tripID: b.id).environmentObject(model) }
        .task(id: model.revision) {
            let since = Date().addingTimeInterval(-7 * 86_400)
            trips = ((try? model.store.trips(overlapping: since, Date())) ?? []).filter(\.needsReview).reversed()
            let freq = (try? model.store.frequentModes(limit: 4)) ?? []
            quick = Array((freq + [.walk, .bus, .subway, .car]).reduce(into: [TravelMode]()) { if !$0.contains($1) { $0.append($1) } }.prefix(4))
        }
    }
}
