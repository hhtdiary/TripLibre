import SwiftUI
import MapKit
import HHTCore

struct PlacesView: View {
    @EnvironmentObject var model: AppModel
    enum Sort: String, CaseIterable, Identifiable {
        case time = "Time", visits = "Visits", recent = "Recent", name = "Name"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .time: return "Most time"
            case .visits: return "Visits"
            case .recent: return "Recent"
            case .name: return "A–Z"
            }
        }
    }

    @State private var places: [Place] = []
    @State private var stats: [String: TravelStore.PlaceStats] = [:]
    @State private var query = ""
    @State private var sort: Sort = .time
    @State private var namedOnly = false
    @State private var pendingDelete: Place?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    private let tilts: [Double] = [-1.5, 1.5, 1, -1, -1, 1.5]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(places.count) spot\(places.count == 1 ? "" : "s") on your map")
                    .font(.toon(15, .heavy)).foregroundStyle(Toon.muted)
                searchField
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Sort.allCases) { s in pill(s.title, on: sort == s) { sort = s } }
                        pill("Named", on: namedOnly, icon: namedOnly ? "checkmark" : nil) { namedOnly.toggle() }
                    }
                    .padding(.vertical, 4).padding(.trailing, 4)
                }

                let named = shown.filter(\.isNamed)
                let unnamed = shown.filter { !$0.isNamed }
                if shown.isEmpty {
                    HStack(spacing: 12) {
                        Mascot(size: 44)
                        Text(query.isEmpty ? "No places yet. They appear once you've stayed somewhere a few minutes."
                                           : "No places match “\(query)”.")
                            .font(.toon(14, .bold)).foregroundStyle(Toon.muted)
                    }
                    .padding(.top, 8)
                }
                if !named.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(named.enumerated()), id: \.element.id) { i, p in
                            NavigationLink { PlaceDetailView(placeID: p.id) } label: {
                                PlaceTile(place: p, stats: stats[p.id]).tilt(tilts[i % tilts.count])
                            }
                            .buttonStyle(.plain)
                            .contextMenu { deleteButton(p) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !unnamed.isEmpty {
                    SectionLabel(text: "Waiting for a name").padding(.top, 6)
                    ForEach(unnamed) { p in
                        NavigationLink { PlaceDetailView(placeID: p.id) } label: {
                            UnnamedPlaceRow(place: p, stats: stats[p.id])
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(p) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(ToonBackground())
        .navigationTitle("Places")
        .confirmationDialog("Delete \(pendingDelete.flatMap { $0.isNamed ? $0.displayName : nil } ?? "this place")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { p in
            Button("Delete place and its \(visitWord(stats[p.id]?.visitCount ?? 0))", role: .destructive) {
                model.perform { try model.edit.deletePlace(p.id) }
            }
        } message: { _ in Text(PlaceDeletion.explanation) }
        .task(id: model.revision) {
            places = (try? model.store.places()) ?? []
            stats = (try? model.store.placeStats()) ?? [:]
        }
    }

    private func deleteButton(_ p: Place) -> some View {
        Button(role: .destructive) { pendingDelete = p } label: { Label("Delete place", systemImage: "trash") }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .bold)).foregroundStyle(Toon.ink)
            TextField("Search places", text: $query)
                .font(.toon(15, .bold)).foregroundStyle(Toon.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Toon.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .toonCard(radius: 25, shadow: 3)
    }

    private func pill(_ title: String, on: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).fontWeight(.black) }
                Text(title)
            }
        }
        .buttonStyle(ToonButtonStyle(fill: on ? Toon.ink : Toon.paper, height: 36, fontSize: 13,
                                     shadow: on ? 0 : 2, text: on ? .white : Toon.ink))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var shown: [Place] {
        var ps = places
        if namedOnly { ps = ps.filter(\.isNamed) }
        if !query.isEmpty {
            ps = ps.filter { $0.displayName.localizedCaseInsensitiveContains(query) || ($0.code ?? "").localizedCaseInsensitiveContains(query)
                || ($0.city ?? "").localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .time: return ps.sorted { (stats[$0.id]?.totalDwell ?? 0) > (stats[$1.id]?.totalDwell ?? 0) }
        case .visits: return ps.sorted { (stats[$0.id]?.visitCount ?? 0) > (stats[$1.id]?.visitCount ?? 0) }
        case .recent: return ps.sorted { (stats[$0.id]?.lastVisit ?? .distantPast) > (stats[$1.id]?.lastVisit ?? .distantPast) }
        case .name: return ps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }
}

/// Named place as a square sticker in the two-column grid.
struct PlaceTile: View {
    let place: Place
    let stats: TravelStore.PlaceStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToonChip(symbol: place.category?.symbol ?? "mappin", color: place.toonColor, size: 52)
            Text(place.displayName)
                .font(.toon(18, .bold)).foregroundStyle(Toon.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
            Text("\(stats?.visitCount ?? 0) visits · \(Fmt.hours(stats?.totalDwell ?? 0))"
                 + (stats?.lastVisit.map { "\nlast \(Fmt.shortDay($0))" } ?? ""))
                .font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(14)
        .toonCard(radius: 22, shadow: 4)
        .overlay(alignment: .topTrailing) {
            if place.favorite {
                Image(systemName: "star.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Toon.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Toon.sun))
                    .overlay(Circle().strokeBorder(Toon.ink, lineWidth: 2))
                    .offset(x: 8, y: -8)
                    .accessibilityLabel("Favorite")
            }
        }
    }
}

/// Unnamed place: dashed sticker with a "Name it" nudge (the whole row opens the place).
struct UnnamedPlaceRow: View {
    let place: Place
    let stats: TravelStore.PlaceStats?

    var body: some View {
        HStack(spacing: 12) {
            ToonChip(symbol: place.category?.symbol ?? "mappin", color: Toon.stone, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.address ?? "Unnamed place").font(.toon(15, .heavy)).foregroundStyle(Toon.ink).lineLimit(2)
                Text("\(stats?.visitCount ?? 0) visits · \(Fmt.hours(stats?.totalDwell ?? 0))"
                     + (stats?.lastVisit.map { " · last \(Fmt.shortDay($0))" } ?? ""))
                    .font(.toon(12, .bold)).foregroundStyle(Toon.muted)
            }
            Spacer(minLength: 0)
            Text("Name it")
                .font(.toon(13, .black)).foregroundStyle(Toon.ink)
                .padding(.horizontal, 14).frame(height: 38)
                .toonCard(Toon.accent, radius: 19, shadow: 2)
        }
        .padding(14)
        .toonCard(Toon.cream, radius: 22, shadow: 0, dashed: true)
    }
}

struct PlaceDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let placeID: String

    @State private var place: Place?
    @State private var draft: Place?
    @State private var visits: [Visit] = []
    @State private var mergeCandidates: [Place] = []
    @State private var showMerge = false
    @State private var radiusText = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let p = draft {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: p.coordinate.cl, latitudinalMeters: max(500, p.radius * 5),
                                                                    longitudinalMeters: max(500, p.radius * 5)))) {
                        MapCircle(center: p.coordinate.cl, radius: p.radius).foregroundStyle(Toon.accent.opacity(0.15))
                            .stroke(Toon.ink, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                        ForEach(visits.prefix(200)) { v in
                            MapCircle(center: v.coordinate.cl, radius: 4).foregroundStyle(Toon.accent).stroke(Toon.ink, lineWidth: 1)
                        }
                    }
                    .frame(height: 200).listRowInsets(EdgeInsets())
                }
                Section("Place") {
                    TextField("Name", text: Binding(get: { draft?.name ?? "" }, set: { draft?.name = $0.isEmpty ? nil : $0 }))
                    PlaceCategoryPicker(selection: Binding(get: { draft?.category }, set: { draft?.category = $0 }))
                    TextField("Code (IATA, station…)", text: Binding(get: { draft?.code ?? "" }, set: { draft?.code = $0.isEmpty ? nil : $0.uppercased() }))
                        .capsKeyboard()
                    HStack {
                        Text("Radius")
                        Slider(value: Binding(get: { draft?.radius ?? 80 }, set: { draft?.radius = $0.rounded() }), in: 30...2000, step: 10)
                        Text("\(Int(p.radius)) m").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                    Toggle("Favorite", isOn: Binding(get: { draft?.favorite ?? false }, set: { draft?.favorite = $0 }))
                }
                Section("Location info") {
                    TextField("Address", text: Binding(get: { draft?.address ?? "" }, set: { draft?.address = $0.isEmpty ? nil : $0 }))
                    TextField("City", text: Binding(get: { draft?.city ?? "" }, set: { draft?.city = $0.isEmpty ? nil : $0 }))
                    TextField("Region / state", text: Binding(get: { draft?.region ?? "" }, set: { draft?.region = $0.isEmpty ? nil : $0 }))
                    TextField("Country", text: Binding(get: { draft?.country ?? "" }, set: { draft?.country = $0.isEmpty ? nil : $0 }))
                    TextField("Notes", text: Binding(get: { draft?.notes ?? "" }, set: { draft?.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }
                if draft != place {
                    Section {
                        Button("Save changes") { model.perform { try model.edit.updatePlace(draft!) } }
                        Button("Discard", role: .cancel) { draft = place }
                    }
                }
                Section {
                    Button { showMerge = true } label: { Label("Merge into another place…", systemImage: "arrow.triangle.merge") }
                } footer: { Text("Use when the same real place was detected twice. All visits move; nothing is lost.") }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("This isn't a real place", systemImage: "trash") }
                } footer: { Text("Deletes the place and its \(visitWord(visits.count)); trips around them are joined.") }

                Section("\(visits.count) visits") {
                    ForEach(visits.prefix(100)) { v in
                        NavigationLink { DayView(day: Calendar.current.startOfDay(for: v.arrival), fixedDay: true) } label: {
                            HStack {
                                Text(Fmt.shortDay(v.arrival))
                                Spacer()
                                Text("\(Fmt.time(v.arrival))–\(v.departure.map { Fmt.time($0) } ?? "now") · \(Fmt.duration(v.duration()))")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            } else {
                Text("This place no longer exists (it may have been merged or deleted).")
            }
        }
        .toonBackground()
        .navigationTitle(place?.displayName ?? "Place")
        .inlineTitle()
        .task(id: model.revision) { load() }
        .confirmationDialog("Delete this place?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete place and its \(visitWord(visits.count))", role: .destructive) {
                model.perform { try model.edit.deletePlace(placeID) }
                dismiss()
            }
        } message: { Text(PlaceDeletion.explanation) }
        .sheet(isPresented: $showMerge) {
            NavigationStack {
                List(mergeCandidates) { c in
                    Button {
                        model.perform { try model.edit.mergePlaces(placeID, into: c.id) }
                        showMerge = false
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(c.displayName)
                            if let p = place { Text(Fmt.distance(Geo.distance(p.coordinate, c.coordinate)) + " away").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .navigationTitle("Merge into…")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showMerge = false } } }
            }
        }
    }

    private func load() {
        place = try? model.store.place(placeID)
        if place?.mergedInto != nil || place?.deleted == true { place = nil }
        draft = place
        visits = (try? model.store.visits(atPlace: placeID)) ?? []
        if let p = place {
            mergeCandidates = ((try? model.store.places()) ?? []).filter { $0.id != p.id }
                .sorted { Geo.distance($0.coordinate, p.coordinate) < Geo.distance($1.coordinate, p.coordinate) }
                .prefix(40).map { $0 }
        }
    }
}

enum PlaceDeletion {
    static let explanation = "Use this for spots that were never real stops (GPS noise, places you don't recognise). "
        + "Visits there leave your diary and the trips before/after are joined. If it is the same place as another one, merge instead."
}

private func visitWord(_ n: Int) -> String { n == 1 ? "1 visit" : "\(n) visits" }

/// Form row that opens a grouped, searchable list of place categories (issue #56).
/// Categories already used by your places are listed first.
struct PlaceCategoryPicker: View {
    @Binding var selection: PlaceCategory?

    var body: some View {
        NavigationLink {
            PlaceCategoryList(selection: $selection)
        } label: {
            LabeledContent("Category") {
                if let c = selection { Label(c.label, systemImage: c.symbol) } else { Text("None") }
            }
        }
    }
}

private struct PlaceCategoryList: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: PlaceCategory?
    @State private var query = ""
    @State private var used: [PlaceCategory] = []

    var body: some View {
        List {
            if query.isEmpty {
                Section { row(nil) }
                if !used.isEmpty {
                    Section("Your categories") { ForEach(used) { row($0) } }
                }
            }
            ForEach(PlaceCategoryGroup.allCases) { g in
                let cats = g.categories.filter { $0.matches(query) }
                if !cats.isEmpty { Section(g.label) { ForEach(cats) { row($0) } } }
            }
        }
        .searchable(text: $query, prompt: "Search categories")
        .navigationTitle("Category")
        .inlineTitle()
        .onAppear {
            var counts: [PlaceCategory: Int] = [:]
            for p in (try? model.store.places()) ?? [] { if let c = p.category { counts[c, default: 0] += 1 } }
            used = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.label < $1.key.label }.prefix(5).map(\.key)
        }
    }

    private func row(_ c: PlaceCategory?) -> some View {
        Button {
            selection = c
            dismiss()
        } label: {
            HStack {
                Label(c?.label ?? "None", systemImage: c?.symbol ?? "circle.dashed").foregroundStyle(.primary)
                Spacer()
                if selection == c { Image(systemName: "checkmark").foregroundStyle(Toon.accent) }
            }
        }
    }
}
