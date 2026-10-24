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
                Section { ForEach(phases) { ph in Button(ph.name) { period = .phase(ph) } } } header: { Text("Life phases").toonSectionText() }
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
    /// Display-only geometry; stored routes are never modified. Arcs: one per OD pair (see `ODFlows`).
    /// Traces: cleaned GPS geometry per trip id (see `RouteDisplay`).
    @State private var flows: [ODFlows.Flow] = []
    @State private var cleanedRoutes: [String: [[Coordinate]]] = [:]
    @State private var routeLines: [RouteLine] = []
    @State private var metersPerPoint: Double = 16
    @State private var mapWidth: CGFloat = 390
    /// Height of the stats card plus its bottom margin; it grows with Dynamic Type.
    @State private var statsSpace: CGFloat = 92
    @State private var placeUse: [(Place, Int)] = []
    @State private var flights: [Flight] = []
    @State private var metrics: MobilityMetrics?
    @State private var showRoutes = true
    @State private var showPlaces = true
    @State private var showHull = true
    @State private var showFlights = true
    @State private var routeStyle: RouteStyle = .arcs
    @State private var position: MapCameraPosition = .automatic
    @Environment(\.tabBarSpace) private var tabBarSpace
    @Environment(\.dynamicTypeSize) private var typeSize

    @ViewBuilder private func statPills(_ m: MobilityMetrics) -> some View {
        StatPill(value: Fmt.distance(m.radiusOfGyrationDwell ?? 0), label: "radius of gyration")
        StatPill(value: String(format: "%.1f km²", (m.activitySpaceHullArea ?? 0) / 1e6), label: "hull area")
        StatPill(value: "\(m.uniquePlaces)", label: "places")
        StatPill(value: "\(m.trips)", label: "trips")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if showHull, let hull = metrics?.activitySpaceHull, hull.count >= 3 {
                    MapPolygon(coordinates: hull.map(\.cl)).foregroundStyle(Toon.accent.opacity(0.12))
                        .stroke(Toon.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round, dash: [8, 6]))
                }
                if showRoutes {
                    ForEach(routeLines) { r in
                        MapPolyline(coordinates: r.coords)
                            .stroke(Toon.ink.opacity(0.7), style: StrokeStyle(lineWidth: r.width + 2.5, lineCap: .round))
                        MapPolyline(coordinates: r.coords)
                            .stroke(r.color, style: StrokeStyle(lineWidth: r.width, lineCap: .round))
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
                                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())   // tappable size, not drawn
                                .accessibilityLabel("\(p.isNamed ? p.displayName : "Unnamed place"), \(n) \(n == 1 ? "visit" : "visits")")
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
                if bucket != metersPerPoint {
                    metersPerPoint = bucket
                    if routeStyle == .traces { rebuildRouteLines() }
                }
            }
            // keep the Apple Maps logo / Legal link clear of the stats card and tab bar
            .safeAreaPadding(.bottom, tabBarSpace + (metrics == nil ? 0 : statsSpace))

            if let m = metrics {
                Group {
                    // two by two at accessibility text sizes, where four in a row would each get a few letters
                    if typeSize.isAccessibilitySize {
                        StickerGrid(spacing: 10) { statPills(m) }
                    } else {
                        HStack(alignment: .center, spacing: 6) {
                            Mascot(size: 34, bob: false)
                            statPills(m)
                        }
                    }
                }
                .padding(10)
                .toonCard(radius: 20, shadow: 4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statsSpace = $0 + 16 }
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
                    Picker("Route style", selection: $routeStyle) {
                        ForEach(RouteStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: { Image(systemName: "square.3.layers.3d") }
                .accessibilityLabel("Map layers")
            }
        }
        .task(id: "\(period.id)-\(model.revision)") { load() }
        .onChange(of: routeStyle) { _, _ in rebuildRouteLines() }
    }

    private func load() {
        phases = (try? model.store.lifePhases()) ?? []
        let r = period.range(first: model.store.firstPointDate() ?? (try? model.store.allTrips().first?.departure) ?? nil)
        trips = ((try? model.store.trips(overlapping: r.start, r.end, withSegments: false)) ?? []).filter { r.contains($0.departure) }
        cleanedRoutes = Dictionary(trips.map { ($0.id, RouteDisplay.clean($0.route, hasGap: $0.hasGap)) }) { a, _ in a }
        metrics = try? Analytics.compute(store: model.store, range: r)
        let places = Dictionary(uniqueKeysWithValues: ((try? model.store.places()) ?? []).map { ($0.id, $0) })
        let visits = (try? model.store.visits(overlapping: r.start, r.end)) ?? []
        flows = odFlows(visits, places)
        rebuildRouteLines()
        placeUse = (metrics?.topPlaces ?? []).isEmpty ? [] : placeCounts(visits, places)
        flights = ((try? model.store.flights()) ?? []).filter { f in Fmt.parseYMD(f.date).map(r.contains) ?? true }
        position = .automatic
    }

    private func rebuildRouteLines() {
        switch routeStyle {
        case .arcs:
            routeLines = flows.map { f in
                RouteLine(id: f.id, color: f.mode.color, coords: ODFlows.arc(from: f.origin.coordinate, to: f.destination.coordinate).map(\.cl),
                          width: 3 + min(6, log2(Double(f.trips)) * 1.5))
            }
        case .traces:
            routeLines = trips.filter { $0.mode != .airplane }.flatMap { t -> [RouteLine] in
                let pieces = (cleanedRoutes[t.id] ?? []).map { RouteDisplay.simplify($0, metersPerPoint: metersPerPoint) }
                return pieces.enumerated().compactMap { i, p in
                    p.count >= 2 ? RouteLine(id: "\(t.id)-\(i)", color: t.mode.color, coords: p.map(\.cl), width: 3.5) : nil
                }
            }
        }
    }

    /// Trip endpoints snap to their places so repeated trips between the same places merge into one arc.
    private func odFlows(_ visits: [Visit], _ places: [String: Place]) -> [ODFlows.Flow] {
        let visitByID = Dictionary(visits.map { ($0.id, $0) }) { a, _ in a }
        func endpoint(placeID: String?, visitID: String?, fallback: Coordinate?) -> ODFlows.Endpoint? {
            let v = visitID.flatMap { visitByID[$0] }
            if let pid = placeID ?? v?.placeID, let p = places[pid] { return .init(key: pid, coordinate: p.coordinate) }
            return (v?.coordinate ?? fallback).map { ODFlows.Endpoint(coordinate: $0) }
        }
        let ods = trips.filter { $0.mode != .airplane }.compactMap { t -> (origin: ODFlows.Endpoint, destination: ODFlows.Endpoint, mode: TravelMode)? in
            let route = t.route
            guard let o = endpoint(placeID: t.originPlaceID, visitID: t.originVisitID, fallback: route.first),
                  let d = endpoint(placeID: t.destinationPlaceID, visitID: t.destinationVisitID, fallback: route.last)
            else { return nil }
            return (o, d, t.mode)
        }
        return ODFlows.aggregate(ods)
    }

    private func placeCounts(_ visits: [Visit], _ places: [String: Place]) -> [(Place, Int)] {
        var counts: [String: Int] = [:]
        for v in visits { if let p = v.placeID { counts[p, default: 0] += 1 } }
        return counts.compactMap { k, n in places[k].map { ($0, n) } }
    }
}

/// One drawable line on the overview map: an OD arc or a piece of a trip trace.
private struct RouteLine: Identifiable {
    let id: String
    let color: Color
    let coords: [CLLocationCoordinate2D]
    let width: CGFloat
}

private enum RouteStyle: String, CaseIterable, Identifiable {
    case arcs, traces
    var id: String { rawValue }
    var label: String {
        switch self {
        case .arcs: return "Origin → destination arcs"
        case .traces: return "GPS traces"
        }
    }
}
