import SwiftUI
import MapKit
import HHTCore

/// Shared period selector for Map and Stats.
enum Period: Hashable, Identifiable {
    case week, month, year, all
    case phase(LifePhase)

    var id: String {
        switch self {
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .all: return "all"
        case .phase(let p): return "phase-" + p.id
        }
    }
    var label: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .year: return "Year"
        case .all: return "All time"
        case .phase(let p): return p.name
        }
    }
    func range(first: Date?) -> DateRange {
        switch self {
        case .week: return .lastDays(7)
        case .month: return .lastDays(30)
        case .year: return .lastDays(365)
        case .all: return DateRange(start: first ?? Date(), end: Date())
        case .phase(let p): return DateRange.phase(p) ?? .lastDays(30)
        }
    }
    static func == (a: Period, b: Period) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct PeriodPicker: View {
    @Binding var period: Period
    var phases: [LifePhase]
    var body: some View {
        Menu {
            ForEach([Period.week, .month, .year, .all]) { p in Button(p.label) { period = p } }
            if !phases.isEmpty {
                Section("Life phases") { ForEach(phases) { ph in Button(ph.name) { period = .phase(ph) } } }
            }
        } label: {
            Label(period.label, systemImage: "calendar").labelStyle(.titleAndIcon)
        }
    }
}

struct ExploreMapView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: Period = .month
    @State private var phases: [LifePhase] = []
    @State private var trips: [Trip] = []
    /// Display-only cleaned geometry per trip id (see `RouteDisplay`); stored routes are never modified.
    @State private var cleanedRoutes: [String: [[Coordinate]]] = [:]
    @State private var routeLines: [RouteLine] = []
    @State private var metersPerPoint: Double = 16
    @State private var mapWidth: CGFloat = 390
    @State private var placeUse: [(Place, Int)] = []
    @State private var flights: [Flight] = []
    @State private var metrics: MobilityMetrics?
    @State private var showRoutes = true
    @State private var showPlaces = true
    @State private var showHull = true
    @State private var showFlights = true
    @State private var cleanRoutes = true
    @State private var position: MapCameraPosition = .automatic
    @Environment(\.tabBarSpace) private var tabBarSpace

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if showHull, let hull = metrics?.activitySpaceHull, hull.count >= 3 {
                    MapPolygon(coordinates: hull.map(\.cl)).foregroundStyle(Toon.accent.opacity(0.12))
                        .stroke(Toon.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round, dash: [8, 6]))
                }
                if showRoutes {
                    ForEach(routeLines) { r in
                        MapPolyline(coordinates: r.coords).stroke(Toon.ink.opacity(0.7), lineWidth: 6)
                        MapPolyline(coordinates: r.coords).stroke(r.color, lineWidth: 3.5)
                    }
                }
                if showFlights {
                    ForEach(flights) { f in
                        if let o = f.origin, let d = f.destination {
                            MapPolyline(MKGeodesicPolyline(coordinates: [o.cl, d.cl], count: 2)).stroke(Toon.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
                        }
                    }
                }
                if showPlaces {
                    ForEach(placeUse, id: \.0.id) { p, n in
                        Annotation(p.isNamed ? p.displayName : "", coordinate: p.coordinate.cl) {
                            Circle().fill(p.toonColor == Toon.paper ? Toon.accent : p.toonColor)
                                .frame(width: CGFloat(10 + min(24, sqrt(Double(n)) * 3)), height: CGFloat(10 + min(24, sqrt(Double(n)) * 3)))
                                .overlay(Circle().strokeBorder(Toon.ink, lineWidth: 2))
                        }
                    }
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mapWidth = max(1, $0) }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                let metres = ctx.rect.width * MKMetersPerMapPointAtLatitude(ctx.region.center.latitude)
                // power-of-two buckets so small pans/zooms don't re-simplify every route
                let bucket = pow(2, log2(max(0.5, metres / Double(mapWidth))).rounded())
                if bucket != metersPerPoint { metersPerPoint = bucket; rebuildRouteLines() }
            }
            // keep the Apple Maps logo / Legal link clear of the stats card and tab bar
            .safeAreaPadding(.bottom, tabBarSpace + (metrics == nil ? 0 : 92))

            if let m = metrics {
                HStack(alignment: .center, spacing: 6) {
                    Mascot(size: 34, bob: false)
                    StatPill(value: Fmt.distance(m.radiusOfGyrationDwell ?? 0), label: "radius of gyration")
                    StatPill(value: String(format: "%.1f km²", (m.activitySpaceHullArea ?? 0) / 1e6), label: "hull area")
                    StatPill(value: "\(m.uniquePlaces)", label: "places")
                    StatPill(value: "\(m.trips)", label: "trips")
                }
                .padding(10)
                .toonCard(radius: 20, shadow: 4)
                .padding(.horizontal, 16).padding(.bottom, 16 + tabBarSpace)
            }
        }
        .navigationTitle("Map")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .navigation) { PeriodPicker(period: $period, phases: phases) }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Routes", isOn: $showRoutes)
                    Toggle("Places", isOn: $showPlaces)
                    Toggle("Activity space (convex hull)", isOn: $showHull)
                    Toggle("Flights", isOn: $showFlights)
                    Section("Display only — recorded data is unchanged") {
                        Toggle("Clean up GPS drift", isOn: $cleanRoutes)
                    }
                } label: { Image(systemName: "square.3.layers.3d") }
            }
        }
        .task(id: "\(period.id)-\(model.revision)") { load() }
        .onChange(of: cleanRoutes) { _, _ in rebuildRouteLines() }
    }

    private func load() {
        phases = (try? model.store.lifePhases()) ?? []
        let r = period.range(first: model.store.firstPointDate() ?? (try? model.store.allTrips().first?.departure) ?? nil)
        trips = ((try? model.store.trips(overlapping: r.start, r.end, withSegments: false)) ?? []).filter { r.contains($0.departure) }
        cleanedRoutes = Dictionary(trips.map { ($0.id, RouteDisplay.clean($0.route, hasGap: $0.hasGap)) }) { a, _ in a }
        rebuildRouteLines()
        metrics = try? Analytics.compute(store: model.store, range: r)
        let places = Dictionary(uniqueKeysWithValues: ((try? model.store.places()) ?? []).map { ($0.id, $0) })
        placeUse = (metrics?.topPlaces ?? []).isEmpty ? [] : placeCounts(r, places)
        flights = ((try? model.store.flights()) ?? []).filter { f in Fmt.parseYMD(f.date).map(r.contains) ?? true }
        position = .automatic
    }

    private func rebuildRouteLines() {
        routeLines = trips.filter { $0.mode != .airplane }.flatMap { t -> [RouteLine] in
            let pieces = cleanRoutes
                ? (cleanedRoutes[t.id] ?? []).map { RouteDisplay.simplify($0, metersPerPoint: metersPerPoint) }
                : [t.route]
            return pieces.enumerated().compactMap { i, p in
                p.count >= 2 ? RouteLine(id: "\(t.id)-\(i)", color: t.mode.color, coords: p.map(\.cl)) : nil
            }
        }
    }

    private func placeCounts(_ r: DateRange, _ places: [String: Place]) -> [(Place, Int)] {
        let visits = (try? model.store.visits(overlapping: r.start, r.end)) ?? []
        var counts: [String: Int] = [:]
        for v in visits { if let p = v.placeID { counts[p, default: 0] += 1 } }
        return counts.compactMap { k, n in places[k].map { ($0, n) } }
    }
}

/// One drawable piece of a trip route on the overview map.
private struct RouteLine: Identifiable {
    let id: String
    let color: Color
    let coords: [CLLocationCoordinate2D]
}
