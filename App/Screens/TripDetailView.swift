import SwiftUI
import MapKit
import HHTCore

struct TripDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let tripID: String

    @State private var trip: Trip?
    @State private var origin: (Visit?, Place?) = (nil, nil)
    @State private var destination: (Visit?, Place?) = (nil, nil)
    @State private var frequent: [TravelMode] = []
    @State private var notes = ""
    @State private var history: [AuditEntry] = []
    @State private var costs: [Expense] = []
    @State private var costSheet: CostSheet?
    @State private var confirmDelete = false
    @State private var showSplit = false
    @State private var showAllModes = false
    /// Mode tiles get wider as their labels grow with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var modeTileWidth: CGFloat = 88
    @State private var showModeChange = false
    @State private var editingSegment: IDBox?

    var body: some View {
        NavigationStack {
            Group {
                if let t = trip { content(t) } else { ProgressView() }
            }
            .navigationTitle("Trip")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveNotes(); dismiss() }.confirmTint() } }
            .task(id: model.revision) { load() }
        }
    }

    @ViewBuilder private func content(_ t: Trip) -> some View {
        List {
            Section {
                TripMap(trip: t, origin: origin.1?.coordinate ?? origin.0?.coordinate,
                        destination: destination.1?.coordinate ?? destination.0?.coordinate)
                    .frame(height: 220).listRowInsets(EdgeInsets())
                VStack(alignment: .leading, spacing: 4) {
                    Label(origin.1?.displayName ?? "Unknown origin", systemImage: "circle")
                    Label(destination.1?.displayName ?? "Unknown destination", systemImage: "mappin.circle.fill")
                    Text("\(Fmt.dateTime(t.departure)) → \(Fmt.time(t.arrival))  ·  \(Fmt.duration(t.duration))  ·  \(Fmt.distance(t.distance))")
                        .font(.caption).foregroundStyle(Toon.muted)
                }
            }

            Section {
                modeGrid(t)
                if t.modeUser != nil {
                    Button("Reset to automatic (\(t.modeAuto?.label ?? "unknown"))") {
                        model.perform { try model.edit.setTripMode(t.id, nil) }
                    }
                    .font(.footnote)
                }
            } header: { Text("Mode").toonSectionText() }

            Section {
                if t.segments.count > 1 {
                    ForEach(t.segments) { s in
                        Button { editingSegment = IDBox(id: s.id) } label: {
                            HStack {
                                ModeIcon(mode: s.mode, size: 24)
                                VStack(alignment: .leading) {
                                    HStack(spacing: 6) {
                                        Text(s.mode.label)
                                        Text(s.isUserSet ? "You" : "Auto")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(s.isUserSet ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                                                        in: Capsule())
                                            .accessibilityLabel(s.isUserSet ? "Set by you" : "Detected automatically")
                                    }
                                    Text("\(Fmt.time(s.start))–\(Fmt.time(s.end)) · \(Fmt.duration(s.end.timeIntervalSince(s.start))) · \(Fmt.distance(s.distance))")
                                        .font(.caption).foregroundStyle(Toon.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { showModeChange = true } label: {
                    Label("I changed mode on the way", systemImage: "arrow.triangle.branch")
                }
            } header: { Text("Segments").toonSectionText() } footer: {
                Text(t.segments.count > 1
                     ? "Tap a segment to change its mode or times, or remove it. Segments you set are kept when the day is reprocessed."
                     : "Add a segment for each part of the trip, e.g. subway, then walk.")
                    .toonSectionText()
            }

            Section {
                Picker("Purpose", selection: Binding(
                    get: { t.purpose },
                    set: { p in model.perform { try model.edit.setTripPurpose(t.id, p) } })) {
                    Text(destinationDefaultPurpose.map { "Auto (\($0.label))" } ?? "Not set").tag(TripPurpose?.none)
                    ForEach(TripPurpose.allCases) { p in Text(p.label).tag(TripPurpose?.some(p)) }
                }
            } header: { Text("Purpose (activity at destination)").toonSectionText() }

            CostsSection(costs: costs, target: .trip(t), sheet: $costSheet)

            Section {
                TextField("Add a note", text: $notes, axis: .vertical)
                    .onSubmit(saveNotes)
            } header: { Text("Notes").toonSectionText() }

            Section {
                if t.userStatus == .auto {
                    Button { model.perform { try model.edit.confirm(tripID: t.id) } } label: {
                        Label("Looks right", systemImage: "checkmark.circle")
                    }
                }
                Button { showSplit = true } label: { Label("I stopped somewhere (split trip)", systemImage: "scissors") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("This trip didn't happen", systemImage: "trash")
                }
            }

            Section {
                LabeledContent("Automatic mode", value: "\(t.modeAuto?.label ?? "–") (\(Fmt.percent(t.modeConfidence)))")
                LabeledContent("Status", value: t.userStatus.rawValue)
                LabeledContent("Source", value: t.source.rawValue)
                if t.hasGap { LabeledContent("GPS gap", value: "yes – route partly straight-line") }
                LabeledContent("Trip ID", value: String(t.id.prefix(8)))
                if !history.isEmpty {
                    DisclosureGroup("Edit history (\(history.count))") {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                            VStack(alignment: .leading) {
                                Text("\(h.action) \(h.field ?? "")").font(.caption.weight(.medium))
                                Text("\(h.oldValue ?? "∅") → \(h.newValue ?? "∅") · \(Fmt.dateTime(h.timestamp))")
                                    .font(.caption2).foregroundStyle(Toon.muted)
                            }
                        }
                    }
                }
            } header: { Text("Details").toonSectionText() }
        }
        .groupedList()
        .confirmationDialog("Remove this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove and join the visits before/after", role: .destructive) {
                model.perform { try model.edit.deleteTrip(t.id) }
                dismiss()
            }
        } message: {
            Text("Use this for GPS jumps. The stay before and after become one visit. Raw data is kept.")
        }
        .sheet(item: $costSheet) { c in CostEntrySheet(target: c.target, existing: c.existing).environmentObject(model) }
        .sheet(isPresented: $showSplit) { SplitTripSheet(trip: t).environmentObject(model) }
        .sheet(isPresented: $showModeChange) { ModeChangeSheet(trip: t).environmentObject(model) }
        .sheet(item: $editingSegment) { b in
            if let i = t.segments.firstIndex(where: { $0.id == b.id }) {
                SegmentEditSheet(trip: t, index: i).environmentObject(model)
            }
        }
    }

    private var destinationDefaultPurpose: TripPurpose? {
        destination.0?.purpose ?? destination.1?.category?.defaultPurpose
    }

    private func modeGrid(_ t: Trip) -> some View {
        let primary: [TravelMode] = {
            var list = frequent
            for m in [TravelMode.walk, .bicycle, .bus, .subway, .car, .carPassenger, .taxi, .commuterRail, .lightRail, .airplane]
            where !list.contains(m) { list.append(m) }
            return Array(list.prefix(showAllModes ? 99 : 8))
        }()
        let all = showAllModes ? primary + TravelMode.allCases.filter { !primary.contains($0) } : primary
        return VStack(alignment: .leading) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: modeTileWidth), spacing: 8)], spacing: 8) {
                ForEach(all) { m in
                    Button { model.perform { try model.edit.setTripMode(t.id, m) } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: m.symbol).font(.title3)
                            Text(m.label).font(.caption2).toonLineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(t.mode == m ? m.color.opacity(0.25) : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.mode == m ? m.color : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(showAllModes ? "Fewer modes" : "All modes…") { showAllModes.toggle() }.font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private func saveNotes() {
        guard let t = trip, notes != (t.notes ?? "") else { return }
        model.perform { try model.edit.setNotes(tripID: t.id, notes) }
    }

    private func load() {
        guard let t = try? model.store.trip(tripID) else { trip = nil; return }
        trip = t
        notes = t.notes ?? ""
        let ov = t.originVisitID.flatMap { try? model.store.visit($0) }
        let dv = t.destinationVisitID.flatMap { try? model.store.visit($0) }
        origin = (ov, (ov?.placeID ?? t.originPlaceID).flatMap { try? model.store.place($0) })
        destination = (dv, (dv?.placeID ?? t.destinationPlaceID).flatMap { try? model.store.place($0) })
        frequent = (try? model.store.frequentModes(limit: 4)) ?? []
        history = (try? model.store.auditLog(entityID: t.id)) ?? []
        costs = (try? model.store.expenses(tripID: t.id)) ?? []
    }
}

struct TripMap: View {
    let trip: Trip
    let origin: Coordinate?
    let destination: Coordinate?

    var body: some View {
        Map(initialPosition: .automatic) {
            if trip.segments.count > 1 {
                ForEach(trip.segments) { s in
                    if let p = s.routePolyline {
                        MapPolyline(coordinates: Polyline.decode(p).map(\.cl)).stroke(s.mode.color, lineWidth: 5)
                    }
                }
            } else if trip.mode == .airplane, let o = origin, let d = destination {
                MapPolyline(MKGeodesicPolyline(coordinates: [o.cl, d.cl], count: 2)).stroke(trip.mode.color, lineWidth: 4)
            } else {
                MapPolyline(coordinates: trip.route.map(\.cl)).stroke(trip.mode.color, lineWidth: 5)
            }
            if let o = origin { Marker("Start", systemImage: "circle", coordinate: o.cl).tint(.gray) }
            if let d = destination { Marker("End", systemImage: "mappin", coordinate: d.cl).tint(.red) }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

/// Insert a stop into a trip.
struct SplitTripSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    // Seeded in init, not onAppear: the picker ranges below are built on first render and trap if inverted.
    @State private var start: Date
    @State private var end: Date
    @State private var placeID: String?
    @State private var pin: Coordinate?
    @State private var places: [Place] = []

    init(trip: Trip) {
        self.trip = trip
        let t = SplitTimes.trip(departure: trip.departure, arrival: trip.arrival)
        _start = State(initialValue: t.stopStart)
        _end = State(initialValue: t.stopEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Arrived at stop", selection: $start, in: .ordered(trip.departure, trip.arrival), displayedComponents: [.hourAndMinute])
                    DatePicker("Left stop", selection: $end, in: .ordered(start, trip.arrival), displayedComponents: [.hourAndMinute])
                } footer: { Text("The trip becomes two trips with a visit in between.").toonSectionText() }
                Section {
                    stopMap.frame(height: 260).listRowInsets(EdgeInsets())
                    Picker("Place", selection: $placeID) {
                        Text(pin == nil ? "Guess from GPS (new place)" : "Pin on map (new place)").tag(String?.none)
                        ForEach(places) { p in Text(p.displayName).tag(String?.some(p.id)) }
                    }
                } header: { Text("Where").toonSectionText() } footer: {
                    Text("Tap the map where you stopped. Without a pin the stop goes where GPS last saw you, which can be far off if the trip has a GPS gap.")
                        .toonSectionText()
                }
            }
            .navigationTitle("Add stop")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        let stop = SplitTimes.tripStop(start: start, end: end, arrival: trip.arrival)
                        model.perform { _ = try model.edit.splitTrip(trip.id, stopStart: stop.stopStart, stopEnd: stop.stopEnd,
                                                                       placeID: placeID, at: pin) }
                        dismiss()
                    }
                    .confirmTint()
                }
            }
            .onChange(of: start) { _, v in end = max(end, v) }
            // Choosing a saved place moves the pin there; tapping the map (below) goes back to a new place.
            .onChange(of: placeID) { _, id in
                if let p = places.first(where: { $0.id == id }) { pin = p.coordinate }
            }
            .onAppear {
                places = ((try? model.store.places()) ?? []).filter(\.isNamed)
            }
        }
    }

    private var stopMap: some View {
        MapReader { proxy in
            Map(initialPosition: .automatic) {
                MapPolyline(coordinates: trip.route.map(\.cl)).stroke(trip.mode.color, lineWidth: 4)
                if let p = pin { Marker("Stop", systemImage: "mappin", coordinate: p.cl).tint(.orange) }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .store, .restaurant, .cafe])))
            .onTapGesture { point in
                guard let c = proxy.convert(point, from: .local) else { return }
                pin = Coordinate(c.latitude, c.longitude)
                placeID = nil
            }
        }
    }
}

/// "I changed mode on the way": split the trip's segments at a time, e.g. subway until 18:12, then walk.
struct ModeChangeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    // Seeded in init, not onAppear: the picker range below is built on first render (see SplitTripSheet).
    @State private var time: Date
    @State private var before: TravelMode
    @State private var after: TravelMode

    init(trip: Trip) {
        self.trip = trip
        let t = SplitTimes.trip(departure: trip.departure, arrival: trip.arrival).stopStart
        _time = State(initialValue: t)
        let running = trip.segments.first { $0.start < t && t < $0.end }?.mode ?? trip.mode
        _before = State(initialValue: running)
        _after = State(initialValue: running == .walk ? trip.mode : .walk)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Before", selection: $before) { modeOptions }
                    DatePicker("Changed at", selection: $time, in: .ordered(trip.departure, trip.arrival),
                               displayedComponents: [.hourAndMinute])
                    Picker("After", selection: $after) { modeOptions }
                } footer: {
                    Text("\(Fmt.time(trip.departure))–\(Fmt.time(trip.arrival)). The trip stays one trip with two segments; both are kept when the day is reprocessed.")
                        .toonSectionText()
                }
            }
            .navigationTitle("Change of mode")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let at = time, mode = before
                        model.perform {
                            try model.edit.addModeChange(tripID: trip.id, at: at, mode: after)
                            if let s = try model.store.trip(trip.id)?.segments.first(where: { abs($0.end.timeIntervalSince(at)) < 1 }), s.mode != mode || !s.isUserSet {
                                try model.edit.setSegmentMode(s.id, mode)
                            }
                        }
                        dismiss()
                    }
                    .confirmTint()
                }
            }
        }
    }

    @ViewBuilder private var modeOptions: some View {
        ForEach(TravelMode.allCases) { m in Label(m.label, systemImage: m.symbol).tag(m) }
    }
}

/// Change one segment's mode or end time, or remove it.
struct SegmentEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let index: Int
    @State private var mode: TravelMode
    @State private var end: Date
    @State private var confirmRemove = false

    init(trip: Trip, index: Int) {
        self.trip = trip
        self.index = index
        _mode = State(initialValue: trip.segments[index].mode)
        _end = State(initialValue: trip.segments[index].end)
    }

    private var segment: TripSegment { trip.segments[index] }
    private var next: TripSegment? { trip.segments.indices.contains(index + 1) ? trip.segments[index + 1] : nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(TravelMode.allCases) { m in Label(m.label, systemImage: m.symbol).tag(m) }
                    }
                    LabeledContent("Started", value: Fmt.time(segment.start))
                    if let n = next {
                        DatePicker("Ended", selection: $end, in: .ordered(segment.start, n.end), displayedComponents: [.hourAndMinute])
                    } else {
                        LabeledContent("Ended", value: Fmt.time(segment.end))
                    }
                    LabeledContent("Distance", value: Fmt.distance(segment.distance))
                } footer: {
                    Text(segment.isUserSet
                         ? "Set by you; kept when the day is reprocessed."
                         : "Detected automatically (\(Fmt.percent(segment.modeConfidence))). Saving marks it as set by you.")
                        .toonSectionText()
                }
                Section {
                    Button(role: .destructive) { confirmRemove = true } label: { Label("Remove this segment", systemImage: "trash") }
                } footer: {
                    Text(index > 0 ? "Its time joins the segment before it." : "Its time joins the segment after it.")
                        .toonSectionText()
                }
            }
            .navigationTitle("Segment \(index + 1) of \(trip.segments.count)")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let id = segment.id, newMode = mode, newEnd = end
                        let modeChanged = newMode != segment.mode || !segment.isUserSet
                        let endChanged = next != nil && abs(newEnd.timeIntervalSince(segment.end)) >= 1
                        model.perform {
                            if modeChanged { try model.edit.setSegmentMode(id, newMode) }
                            if endChanged { try model.edit.setSegmentEnd(id, to: newEnd) }
                        }
                        dismiss()
                    }
                    .confirmTint()
                }
            }
            .confirmationDialog("Remove this segment?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    let id = segment.id
                    model.perform { try model.edit.removeSegment(id) }
                    dismiss()
                }
            }
        }
    }
}
