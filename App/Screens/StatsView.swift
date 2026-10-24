import SwiftUI
import Charts
import HHTCore

struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var period: Period = .month
    @State private var compare: Period?
    @State private var phases: [LifePhase] = []
    @State private var m: MobilityMetrics?
    @State private var c: MobilityMetrics?
    @State private var shareBasis = 0   // 0 trips, 1 distance, 2 time
    @State private var flightStats = Analytics.FlightStats()
    @State private var spending: SpendingSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(compare.map { "\(period.label) vs \($0.label)" } ?? period.label)
                    .font(.toon(15, .heavy)).foregroundStyle(Toon.muted)
                periodBar
                if let m {
                    hero(m)
                    stickers(m)
                    if let spending { SpendingStatsCard(summary: spending, period: period) }
                    modes(m)
                    temporal(m)
                    weekdayStickers(m)
                    moreNumbers(m)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(ToonBackground())
        .navigationTitle("Stats")
        .onReceive(model.$route) { r in
            // the "Last 7 days" widget lands here
            guard r == .stats else { return }
            model.route = nil
            period = .week
            compare = nil
        }
        .task(id: "\(period.id)-\(compare?.id ?? "")-\(model.revision)") { load() }
    }

    // MARK: period + compare

    private var periodBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // equal-width pills, or wrapping ones at accessibility text sizes
            if typeSize.isAccessibilitySize {
                ToonFlow { periodPills(equalWidth: false) }
            } else {
                HStack(spacing: 8) { periodPills(equalWidth: true) }
            }
            ToonRowStack(spacing: 8) {
                if !phases.isEmpty {
                    Menu {
                        ForEach(phases) { ph in Button(ph.name) { period = .phase(ph) } }
                    } label: {
                        menuLabel(isPhase ? period.label : "Life phase", symbol: "calendar.badge.clock", on: isPhase)
                    }
                }
                Menu {
                    Button("No comparison") { compare = nil }
                    ForEach([Period.week, .month, .year, .all]) { p in Button(p.label) { compare = p } }
                    ForEach(phases) { ph in Button(ph.name) { compare = .phase(ph) } }
                } label: {
                    menuLabel(compare.map { "vs \($0.label)" } ?? "Compare…", symbol: "arrow.left.arrow.right", on: compare != nil)
                }
            }
        }
    }

    private var isPhase: Bool { if case .phase = period { return true } else { return false } }

    @ViewBuilder private func periodPills(equalWidth: Bool) -> some View {
        ForEach([Period.week, .month, .year, .all]) { p in
            pill(p == .all ? "All" : p.label, on: period == p, equalWidth: equalWidth) { period = p }
        }
    }

    private func pill(_ title: String, on: Bool, equalWidth: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: equalWidth ? .infinity : nil) }
            .buttonStyle(ToonButtonStyle(fill: on ? Toon.ink : Toon.paper, height: 38, fontSize: 13,
                                         shadow: on ? 0 : 2, text: on ? .white : Toon.ink))
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func menuLabel(_ title: String, symbol: String, on: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.toon(13)).foregroundStyle(Toon.ink).toonLineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .toonCard(on ? Toon.sun : Toon.paper, radius: 18, shadow: 2)
    }

    // MARK: design sections

    private func hero(_ m: MobilityMetrics) -> some View {
        MascotSays(text: m.trips == 0 ? "No trips in this period yet. Let's go somewhere!"
                   : "You made \(m.trips) trip\(m.trips == 1 ? "" : "s") across \(m.personDays) active day\(m.personDays == 1 ? "" : "s")"
                     + (c.flatMap { cc in compare.map { cmp in cc.trips < m.trips ? ", \(m.trips - cc.trips) more than \(cmp.label)" : "" } } ?? "")
                     + ". Busy bee!")
    }

    private func stickers(_ m: MobilityMetrics) -> some View {
        StickerGrid {
            sticker(String(format: "%.1f", m.tripsPerDay), "trips / day", Toon.sun, -1.5,
                    delta(m.tripsPerDay, c?.tripsPerDay) { String(format: "%.1f", $0) })
            sticker(Fmt.distance(m.distancePerDay), "distance / day", Toon.lime, 1.5,
                    delta(m.distancePerDay, c?.distancePerDay, Fmt.distance))
            sticker(Fmt.duration(m.travelTimePerDay), "travel time / day", Toon.sky, 1,
                    delta(m.travelTimePerDay, c?.travelTimePerDay, Fmt.duration))
            sticker(Fmt.distance(m.meanTripDistance), "mean trip", Toon.bubblegum, -1,
                    delta(m.meanTripDistance, c?.meanTripDistance, Fmt.distance))
        }
    }

    private func sticker(_ value: String, _ label: String, _ color: Color, _ tilt: Double, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.toon(26, .bold)).monospacedDigit().toonLineLimit(1, minScale: 0.6)
            Text(label).font(.toon(12)).toonLineLimit(1, minScale: 0.8)
            if let sub { Text(sub).font(.toon(11, .heavy)).toonLineLimit(1, minScale: 0.7).padding(.top, 4) }
        }
        .foregroundStyle(Toon.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .toonCard(color, radius: 18, shadow: 4)
        .tilt(tilt)
    }

    /// "▲ 0.3 vs 30 days" when a comparison period is chosen.
    private func delta(_ a: Double, _ b: Double?, _ fmt: (Double) -> String) -> String? {
        guard let b, let compare else { return nil }
        let d = a - b
        if abs(d) < 1e-9 { return "same as \(compare.label)" }
        return "\(d > 0 ? "▲" : "▼") \(fmt(abs(d))) vs \(compare.label)"
    }

    private func modes(_ m: MobilityMetrics) -> some View {
        let total = m.modeShare.reduce(0.0) { $0 + value($1) }
        let rows = m.modeShare.sorted { value($0) > value($1) }
        let top = rows.first.map { total > 0 ? value($0) / total : 0 } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            ToonRowStack(spacing: 8) {
                SectionLabel(text: "How you got around")
                Spacer()
                Menu {
                    Picker("Basis", selection: $shareBasis) {
                        Text("by trips").tag(0); Text("by distance").tag(1); Text("by time").tag(2)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(["by trips", "by distance", "by time"][shareBasis])
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .black))
                    }
                    .font(.toon(13, .heavy)).foregroundStyle(Toon.muted)
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Share basis: \(["by trips", "by distance", "by time"][shareBasis])")
            }
            VStack(alignment: .leading, spacing: 12) {
                if rows.isEmpty {
                    Text("No trips yet.").font(.toon(13, .bold)).foregroundStyle(Toon.muted)
                }
                ForEach(rows) { r in
                    let share = total > 0 ? value(r) / total : 0
                    ToonRowStack(spacing: 10) {
                        ModeIcon(mode: r.mode, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.mode.label)
                                Spacer()
                                if let cs = compareShare(r.mode) {
                                    Text(Fmt.percent(cs)).foregroundStyle(Toon.muted)
                                }
                                Text(Fmt.percent(share)).monospacedDigit()
                            }
                            .font(.toon(13, .black)).foregroundStyle(Toon.ink)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Toon.paper)
                                    Capsule().fill(r.mode.color)
                                        .frame(width: max(10, g.size.width * (top > 0 ? share / top : 0)))
                                    Capsule().strokeBorder(Toon.ink, lineWidth: Toon.line)
                                }
                            }
                            .frame(height: 14)
                        }
                    }
                }
                let groups = ModeGroup.allCases.filter { (m.groupShareByTrips[$0] ?? 0) > 0 || (c?.groupShareByTrips[$0] ?? 0) > 0 }
                if !groups.isEmpty {
                    FlowChips(items: groups.map { g in
                        ("\(g.label) \(Fmt.percent(m.groupShareByTrips[g] ?? 0))"
                         + (c.map { " / \(Fmt.percent($0.groupShareByTrips[g] ?? 0))" } ?? ""), g.color)
                    })
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .toonCard(radius: 22, shadow: 4)
        }
    }

    private func compareShare(_ mode: TravelMode) -> Double? {
        guard let c else { return nil }
        let total = c.modeShare.reduce(0.0) { $0 + value($1) }
        guard total > 0 else { return 0 }
        return (c.modeShare.first { $0.mode == mode }.map(value) ?? 0) / total
    }

    private func value(_ r: ModeShareRow) -> Double {
        switch shareBasis {
        case 1: return r.distance
        case 2: return r.time
        default: return Double(r.trips)
        }
    }

    private func temporal(_ m: MobilityMetrics) -> some View {
        let hours = m.departuresByHour
        let peak = max(1, hours.max() ?? 1)
        let peaks = hours.enumerated().filter { $0.element > 0 }.sorted { $0.element > $1.element }.prefix(2)
            .map(\.offset).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "When you head out")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { h, n in
                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                            .fill(n == 0 ? Color.clear : (peaks.contains(h) ? Toon.accent : Toon.sky))
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                                .stroke(n == 0 ? Color.clear : Toon.ink, lineWidth: 2))
                            .frame(height: n == 0 ? 0 : max(4, 90 * CGFloat(n) / CGFloat(peak)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 92, alignment: .bottom)
                .overlay(alignment: .bottom) { Rectangle().fill(Toon.ink).frame(height: Toon.line) }
                HStack {
                    ForEach(["0h", "6h", "12h", "18h", "24h"], id: \.self) { t in
                        Text(t)
                        if t != "24h" { Spacer() }
                    }
                }
                .font(.toon(11, .black)).foregroundStyle(Toon.muted)
                if !peaks.isEmpty {
                    Text("Peak departures: " + peaks.map { String(format: "%02d:00", $0) }.joined(separator: " and "))
                        .font(.toon(13, .heavy)).foregroundStyle(Toon.ink).padding(.top, 2)
                }
            }
            .padding(14)
            .toonCard(radius: 22, shadow: 4)
        }
    }

    private func weekdayStickers(_ m: MobilityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Weekday vs weekend")
            StickerGrid {
                sticker(m.weekdayTripsPerDay.map { String(format: "%.1f", $0) } ?? "–", "trips on weekdays", Toon.paper, -1,
                        c.flatMap { cc in compare.map { "\($0.label): " + (cc.weekdayTripsPerDay.map { String(format: "%.1f", $0) } ?? "–") } })
                sticker(m.weekendTripsPerDay.map { String(format: "%.1f", $0) } ?? "–", "trips on weekends", Toon.paper, 1,
                        c.flatMap { cc in compare.map { "\($0.label): " + (cc.weekendTripsPerDay.map { String(format: "%.1f", $0) } ?? "–") } })
            }
        }
    }

    // MARK: everything else, kept at the bottom

    private func moreNumbers(_ m: MobilityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "All the numbers").padding(.top, 8)
            card("Mobility volume") {
                row("Person-days observed", "\(m.personDays)", c.map { "\($0.personDays)" })
                row("Trips", "\(m.trips)", c.map { "\($0.trips)" })
                row("Trips / day", String(format: "%.2f", m.tripsPerDay), c.map { String(format: "%.2f", $0.tripsPerDay) })
                row("Distance / day", Fmt.distance(m.distancePerDay), c.map { Fmt.distance($0.distancePerDay) })
                row("Travel time / day", Fmt.duration(m.travelTimePerDay), c.map { Fmt.duration($0.travelTimePerDay) })
                row("Mean trip distance", Fmt.distance(m.meanTripDistance), c.map { Fmt.distance($0.meanTripDistance) })
                row("Mean trip duration", Fmt.duration(m.meanTripDuration), c.map { Fmt.duration($0.meanTripDuration) })
                row("Total distance", Fmt.distance(m.totalDistance), c.map { Fmt.distance($0.totalDistance) })
            }
            card("Modes") {
                ForEach(ModeGroup.allCases, id: \.self) { g in
                    if (m.groupShareByTrips[g] ?? 0) > 0 || (c?.groupShareByTrips[g] ?? 0) > 0 {
                        row("\(g.label) share (trips)", Fmt.percent(m.groupShareByTrips[g] ?? 0), c.map { Fmt.percent($0.groupShareByTrips[g] ?? 0) })
                    }
                }
                row("Mode entropy", m.modeEntropy.map { String(format: "%.2f bits", $0) } ?? "–", c?.modeEntropy.map { String(format: "%.2f", $0) })
            }
            card("When") {
                row("Mean first departure", Fmt.minutesOfDay(m.meanFirstDepartureMinutes), c.map { Fmt.minutesOfDay($0.meanFirstDepartureMinutes) })
                row("SD first departure", m.sdFirstDepartureMinutes.map { String(format: "%.0f min", $0) } ?? "–",
                    c?.sdFirstDepartureMinutes.map { String(format: "%.0f min", $0) })
                row("Mean last arrival", Fmt.minutesOfDay(m.meanLastArrivalMinutes), c.map { Fmt.minutesOfDay($0.meanLastArrivalMinutes) })
                row("Time away from home / day", m.meanTimeAwayFromHomePerDay.map(Fmt.duration) ?? "–",
                    c?.meanTimeAwayFromHomePerDay.map(Fmt.duration))
            }
            card("Places") {
                row("Unique places", "\(m.uniquePlaces)", c.map { "\($0.uniquePlaces)" })
                row("New places (first visit)", "\(m.newPlaces)", c.map { "\($0.newPlaces)" })
                row("Destination entropy", m.destinationEntropy.map { String(format: "%.2f bits", $0) } ?? "–",
                    c?.destinationEntropy.map { String(format: "%.2f", $0) })
                row("Repeat OD share", Fmt.percent(m.repeatODShare), c.map { Fmt.percent($0.repeatODShare) })
                ForEach(m.topPlaces.prefix(6)) { p in
                    ToonRowStack(spacing: 8) {
                        Image(systemName: p.category?.symbol ?? "mappin").frame(width: 22).foregroundStyle(Toon.muted)
                        Text(p.name).toonLineLimit(1)
                        Spacer()
                        Text("\(p.visits)× · \(Fmt.hours(p.dwell))").font(.toon(12, .bold)).foregroundStyle(Toon.muted).monospacedDigit()
                    }
                    .font(.toon(14, .bold))
                }
                if !m.topODPairs.isEmpty {
                    DisclosureGroup("Top origin–destination pairs") {
                        ForEach(m.topODPairs) { od in
                            ToonRowStack(spacing: 8) {
                                Text("\(od.originName) → \(od.destinationName)").toonLineLimit(1)
                                Spacer()
                                Text("\(od.trips)").monospacedDigit()
                            }
                            .font(.toon(12, .bold))
                        }
                    }
                    .font(.toon(14, .heavy))
                }
                let cats = m.dwellByCategory.sorted { $0.value > $1.value }.prefix(6)
                if !cats.isEmpty {
                    DisclosureGroup("Time by place category") {
                        ForEach(Array(cats), id: \.key) { k, v in
                            ToonRowStack(spacing: 8) {
                                Text(PlaceCategory(rawValue: k)?.label ?? "Uncategorized")
                                Spacer()
                                Text(Fmt.hours(v)).monospacedDigit()
                            }
                            .font(.toon(12, .bold))
                        }
                    }
                    .font(.toon(14, .heavy))
                }
            }
            card("Activity space") {
                row("Radius of gyration (dwell-weighted)", m.radiusOfGyrationDwell.map(Fmt.distance) ?? "–", c?.radiusOfGyrationDwell.map(Fmt.distance))
                row("Radius of gyration (visit-weighted)", m.radiusOfGyrationVisits.map(Fmt.distance) ?? "–", c?.radiusOfGyrationVisits.map(Fmt.distance))
                row("Activity space (convex hull)", m.activitySpaceHullArea.map { String(format: "%.1f km²", $0 / 1e6) } ?? "–",
                    c?.activitySpaceHullArea.map { String(format: "%.1f", $0 / 1e6) })
            }
            card("Trip chaining", footer: "Tours need a place categorised as Home.") {
                row("Home-based tours", "\(m.tours)", c.map { "\($0.tours)" })
                row("Mean stops per tour", m.meanStopsPerTour.map { String(format: "%.2f", $0) } ?? "–", c?.meanStopsPerTour.map { String(format: "%.2f", $0) })
                row("Tours with ≥2 stops", Fmt.percent(m.complexTourShare), c.map { Fmt.percent($0.complexTourShare) })
            }
            card("Weekday vs weekend") {
                row("Trips / weekday", m.weekdayTripsPerDay.map { String(format: "%.2f", $0) } ?? "–", c?.weekdayTripsPerDay.map { String(format: "%.2f", $0) })
                row("Trips / weekend day", m.weekendTripsPerDay.map { String(format: "%.2f", $0) } ?? "–", c?.weekendTripsPerDay.map { String(format: "%.2f", $0) })
                row("Active share weekday / weekend",
                    "\(Fmt.percent(m.weekdayModeShare[.active] ?? 0)) / \(Fmt.percent(m.weekendModeShare[.active] ?? 0))")
                row("Transit share weekday / weekend",
                    "\(Fmt.percent(m.weekdayModeShare[.transit] ?? 0)) / \(Fmt.percent(m.weekendModeShare[.transit] ?? 0))")
            }
            if flightStats.flights > 0 {
                card("Flights (all time)") {
                    row("Flights", "\(flightStats.flights)")
                    row("Flight distance", Fmt.distance(flightStats.distance))
                    row("Airports", "\(flightStats.airports.count)")
                    row("Routes", "\(flightStats.routes.count)")
                }
            }
            NavigationLink { MetricsHelpView() } label: {
                Label("How these are calculated", systemImage: "questionmark.circle")
                    .font(.toon(14, .heavy)).underline()
                    .foregroundStyle(Toon.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private func card<C: View>(_ title: String, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ToonRowStack(spacing: 8) {
                Text(title).font(.toon(16, .heavy)).foregroundStyle(Toon.ink)
                if let compare {
                    Spacer()
                    Text("\(period.label) / \(compare.label)").font(.toon(11, .heavy)).foregroundStyle(Toon.muted)
                }
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .tint(Toon.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .toonCard(radius: 20, shadow: 3)
            if let footer { Text(footer).font(.toon(12, .bold)).foregroundStyle(Toon.muted) }
        }
    }

    /// Label and value(s) on one line, or the values under the label at accessibility text sizes.
    private func row(_ label: String, _ value: String, _ other: String? = nil) -> some View {
        ToonRowStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.toon(14, .bold))
            Spacer()
            Text(value).font(.toon(14, .heavy)).monospacedDigit()
            if compare != nil {
                Text(other ?? "–").font(.toon(14, .bold)).monospacedDigit().foregroundStyle(Toon.muted)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .foregroundStyle(Toon.ink)
    }

    private func load() {
        phases = (try? model.store.lifePhases()) ?? []
        let first = model.store.firstPointDate() ?? ((try? model.store.allTrips().first?.departure) ?? nil)
        m = try? Analytics.compute(store: model.store, range: period.range(first: first))
        c = compare.flatMap { try? Analytics.compute(store: model.store, range: $0.range(first: first)) }
        flightStats = Analytics.flightStats((try? model.store.flights()) ?? [])
        // only once there's anything to show: people who don't log costs never see the card
        spending = model.store.hasExpenses() ? try? Analytics.spending(store: model.store, range: period.range(first: first)) : nil
    }
}

/// Wrapping row of small coloured chips.
struct FlowChips: View {
    let items: [(String, Color)]
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                Text(it.0)
                    .font(.toon(12, .black)).foregroundStyle(Toon.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(it.1.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: 2))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

struct MetricsHelpView: View {
    var body: some View {
        List {
            item("Person-day", "A local calendar day with at least one recorded visit or trip. Per-day values divide by person-days, not calendar days, so days without data don't count as zero-travel days.")
            item("Trip", "Movement between two consecutive visits (stays ≥ 5 min within ~100 m). A multimodal journey is one trip with several segments; its main mode follows the HHTS hierarchy (air > rail > transit > car > bike > walk).")
            item("Radius of gyration", "r_g = √(Σ wᵢ·d(pᵢ, c)² / Σ wᵢ), over the places visited in the period, c = weighted spherical centre of mass, d = great-circle distance. Dwell-weighted uses time spent at each place; visit-weighted uses the number of visits.")
            item("Activity space", "Convex hull of all places visited in the period (area in a local equal-distance projection).")
            item("Destination entropy", "Shannon entropy (bits) of the distribution of visits over places. 0 = always the same place; higher = visits spread across more places.")
            item("Mode entropy", "Shannon entropy (bits) of trips over modes.")
            item("Repeat OD share", "Share of trips whose origin→destination place pair already occurred earlier in the period.")
            item("Home-based tour", "The sequence of trips from leaving a Home place to the next arrival at a Home place. Stops per tour = intermediate destinations.")
            item("Time away from home", "24 h minus time at Home places, averaged over observed days that include a Home visit.")
            item("New places", "Places whose first-ever visit falls inside the period.")
        }
        .toonBackground()
        .navigationTitle("Definitions")
    }

    private func item(_ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.headline)
            Text(d).font(.callout).foregroundStyle(Toon.muted)
        }
        .padding(.vertical, 4)
    }
}
