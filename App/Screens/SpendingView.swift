import SwiftUI
import Charts
import HHTCore

/// Where the money went (issue #17): totals, travel vs at destinations, categories, modes, places, and every cost.
/// Opened from Today's "Spent today" card and from the Spending card in Stats.
struct SpendingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var period: Period
    @State private var s: SpendingSummary?
    @State private var costs: [Expense] = []
    @State private var trips: [String: Trip] = [:]
    @State private var visits: [String: Visit] = [:]
    @State private var places: [String: Place] = [:]
    @State private var editing: Expense?
    @State private var adding = false

    init(period: Period = .month) { _period = State(initialValue: period) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // equal-width pills, or wrapping ones at accessibility text sizes
                if typeSize.isAccessibilitySize {
                    ToonFlow { periodPills(equalWidth: false) }
                } else {
                    HStack(spacing: 8) { periodPills(equalWidth: true) }
                }
                if let s {
                    MascotSays(text: line(s))
                    if !s.isEmpty {
                        stickers(s)
                        split(s)
                        if s.byDay.count > 1 { perDay(s) }
                        categories(s)
                        if !s.byMode.isEmpty { modes(s) }
                        if !s.byPlace.isEmpty { placesCard(s) }
                    }
                    list
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(ToonBackground())
        .navigationTitle("Spending")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a cost")
            }
        }
        .sheet(item: $editing) { e in CostEntrySheet(target: .day(e.timestamp), existing: e).environmentObject(model) }
        .sheet(isPresented: $adding) { CostEntrySheet(target: .day(Date())).environmentObject(model) }
        .task(id: "\(period.id)-\(model.revision)") { load() }
    }

    private func money(_ x: Double) -> String { Fmt.money(x, s?.currency ?? Expense.defaultCurrency) }

    private func line(_ s: SpendingSummary) -> String {
        guard !s.isEmpty else {
            return "No costs logged in \(period == .all ? "your diary" : "the last \(period.label)") yet. Tap + or answer my question on Today after a paid trip."
        }
        guard s.hasMainCurrency else { return "Everything here is in other currencies; see the list below." }
        let lead = "\(money(s.total)) over \(s.days) day\(s.days == 1 ? "" : "s")"
        if s.travel > 0 && s.travel >= s.atDestinations { return lead + ", mostly getting around." }
        if s.atDestinations > 0 { return lead + ", mostly once you got there." }
        return lead + "."
    }

    @ViewBuilder private func periodPills(equalWidth: Bool) -> some View {
        ForEach([Period.week, .month, .year, .all]) { p in
            Button { period = p } label: { Text(p == .all ? "All" : p.label).frame(maxWidth: equalWidth ? .infinity : nil) }
                .buttonStyle(ToonButtonStyle(fill: period == p ? Toon.ink : Toon.paper, height: 38, fontSize: 13,
                                             shadow: period == p ? 0 : 2, text: period == p ? .white : Toon.ink))
                .accessibilityAddTraits(period == p ? .isSelected : [])
        }
    }

    // MARK: sections

    private func stickers(_ s: SpendingSummary) -> some View {
        StickerGrid {
            StatSticker(value: money(s.total), label: "spent", color: Toon.sun, tilt: -1.5)
            StatSticker(value: money(s.perDay), label: "per day with costs", color: Toon.lime, tilt: 1.5)
            StatSticker(value: money(s.travel), label: "getting around", color: Toon.sky, tilt: 1)
            StatSticker(value: money(s.atDestinations), label: "at destinations", color: Toon.bubblegum, tilt: -1)
        }
    }

    private func split(_ s: SpendingSummary) -> some View {
        let total = max(s.travel + s.atDestinations, 0.000_1)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(Toon.sky).frame(width: g.size.width * s.travel / total)
                    Rectangle().fill(Toon.bubblegum)
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: Toon.line))
            }
            .frame(height: 18)
            .accessibilityHidden(true)
            // only the text is one element: the contrast audit measures an element's whole frame, and with the bar in
            // it reads the bar's colours as the text's (issue #67). The percentages say what the bar shows.
            ToonRowStack(spacing: 8) {
                Text("Travel \(Fmt.percent(s.travel / total))")
                Spacer()
                Text("At destinations \(Fmt.percent(s.atDestinations / total))")
            }
            .font(.toon(12, .heavy)).foregroundStyle(Toon.muted)
            .accessibilityElement(children: .combine)
        }
        .padding(14)
        .toonCard(radius: 22, shadow: 4)
    }

    private func perDay(_ s: SpendingSummary) -> some View {
        let days = s.byDay.compactMap { k, v in Fmt.parseYMD(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Day by day")
            Chart(days, id: \.0) { d, v in
                BarMark(x: .value("Day", d, unit: .day), y: .value("Spent", v))
                    .foregroundStyle(CostStyle.color)
                    .cornerRadius(3)
            }
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let x = v.as(Double.self) { Text(money(x)) } } } }
            .frame(height: 140)
            .padding(14)
            .toonCard(radius: 22, shadow: 4)
        }
    }

    private func categories(_ s: SpendingSummary) -> some View {
        let top = s.byCategory.first?.total ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "What it went on")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(s.byCategory) { r in
                    // the text alone is the element, as in split(_:)
                    ToonRowStack(spacing: 10) {
                        ToonChip(symbol: r.category.symbol, color: r.category.isTravel ? Toon.sky : Toon.bubblegum, size: 34)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            ToonRowStack(spacing: 8) {
                                Text(r.category.label)
                                Spacer()
                                Text(money(r.total)).monospacedDigit()
                            }
                            .font(.toon(13, .black)).foregroundStyle(Toon.ink)
                            .accessibilityElement(children: .combine)
                            bar(top > 0 ? r.total / top : 0, CostStyle.color).accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(14)
            .toonCard(radius: 22, shadow: 4)
        }
    }

    private func modes(_ s: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Getting around")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(s.byMode) { r in
                    // the text alone is the element, as in split(_:)
                    ToonRowStack(spacing: 10) {
                        ModeIcon(mode: r.mode, size: 34).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            ToonRowStack(spacing: 8) {
                                Text(r.mode.label)
                                Spacer()
                                Text(money(r.total)).monospacedDigit()
                            }
                            .font(.toon(13, .black))
                            Text("\(r.trips) trip\(r.trips == 1 ? "" : "s") · \(money(r.perTrip)) a trip"
                                 + (r.perKm.map { " · \(money(Fmt.usesMetric ? $0 : $0 * 1.609_344))/\(Fmt.usesMetric ? "km" : "mi")" } ?? ""))
                                .font(.toon(12, .bold)).foregroundStyle(Toon.muted).monospacedDigit()
                        }
                        .foregroundStyle(Toon.ink)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Only trips with a cost entered (free ones included) count here.")
                    .font(.toon(11, .bold)).foregroundStyle(Toon.muted)
            }
            .padding(14)
            .toonCard(radius: 22, shadow: 4)
        }
    }

    private func placesCard(_ s: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Where you spent")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(s.byPlace.prefix(6)) { p in
                    ToonRowStack(spacing: 8) {
                        Image(systemName: p.category?.symbol ?? "mappin").frame(width: 22).foregroundStyle(Toon.muted).accessibilityHidden(true)
                        Text(p.name).toonLineLimit(1)
                        Spacer()
                        Text("\(p.count)× · \(money(p.total))").monospacedDigit()
                    }
                    .font(.toon(14, .bold)).foregroundStyle(Toon.ink)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .toonCard(radius: 22, shadow: 4)
        }
    }

    @ViewBuilder private var list: some View {
        if !costs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Every cost")
                let byDay = Dictionary(grouping: costs) { Calendar.current.startOfDay(for: $0.timestamp) }
                ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        ToonRowStack(spacing: 8) {
                            Text(Fmt.shortDay(day))
                            Spacer()
                            Text(Fmt.costs(byDay[day] ?? []) ?? "").monospacedDigit()
                        }
                        .font(.toon(13, .heavy)).foregroundStyle(Toon.muted)
                        .accessibilityElement(children: .combine)
                        VStack(spacing: 0) {
                            ForEach(byDay[day] ?? []) { e in
                                Button { editing = e } label: { row(e) }.buttonStyle(.plain)
                                if e.id != byDay[day]?.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 12)
                        .toonCard(radius: 18, shadow: 3)
                    }
                }
                if let s, !s.otherCurrencies.isEmpty {
                    Text("Totals above are in \(s.currency) only. Also spent "
                         + s.otherCurrencies.sorted { $0.key < $1.key }.map { Fmt.money($0.value, $0.key) }.joined(separator: ", ")
                         + ", not converted.")
                        .font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                }
            }
        }
    }

    private func row(_ e: Expense) -> some View {
        ToonRowStack(spacing: 10) {
            Image(systemName: e.category.symbol).frame(width: 24).foregroundStyle(Toon.muted).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(what(e)).font(.toon(14, .bold)).toonLineLimit(1)
                Text([Fmt.time(e.timestamp, tz: e.timeZone), e.category.label, e.note].compactMap { $0 }.joined(separator: " · "))
                    .font(.toon(12, .bold)).foregroundStyle(Toon.muted).toonLineLimit(1)
            }
            Spacer()
            Text(Fmt.cost(e)).font(.toon(15, .heavy)).monospacedDigit()
        }
        .foregroundStyle(Toon.ink)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// What a cost was for: the trip's mode and destination, the visit's place, or nothing in particular.
    private func what(_ e: Expense) -> String {
        if let t = e.tripID.flatMap({ trips[$0] }) {
            let dest = t.destinationVisitID.flatMap { visits[$0]?.placeID } ?? t.destinationPlaceID
            return t.displayModes.map(\.label).joined(separator: " + ")
                + (dest.flatMap { places[$0] }.flatMap { $0.isNamed ? " to \($0.displayName)" : nil } ?? "")
        }
        if let v = e.visitID.flatMap({ visits[$0] }) {
            return v.placeID.flatMap { places[$0] }.flatMap { $0.isNamed ? "At \($0.displayName)" : nil } ?? "At an unnamed place"
        }
        return e.category.label
    }

    private func bar(_ fraction: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Toon.paper)
                Capsule().fill(color).frame(width: max(10, g.size.width * fraction))
                Capsule().strokeBorder(Toon.ink, lineWidth: Toon.line)
            }
        }
        .frame(height: 14)
    }

    private func load() {
        let store = model.store
        let first = ((try? store.recentExpenses(limit: 1_000_000)) ?? []).last?.timestamp
        let range = period.range(first: first)
        s = try? Analytics.spending(store: store, range: range)
        costs = ((try? store.expenses(from: range.start, to: range.end)) ?? []).reversed()
        var t: [String: Trip] = [:], v: [String: Visit] = [:]
        for id in Set(costs.compactMap(\.tripID)) { if let x = try? store.trip(id), !x.deleted { t[id] = x } }
        for id in Set(costs.compactMap(\.visitID)) { if let x = try? store.visit(id), !x.deleted { v[id] = x } }
        for x in t.values { if let d = x.destinationVisitID, v[d] == nil, let dv = try? store.visit(d) { v[d] = dv } }
        trips = t
        visits = v
        places = Dictionary(uniqueKeysWithValues: ((try? store.places()) ?? []).map { ($0.id, $0) })
    }
}

/// The Stats tab's way into spending: the period's total and split, and a link to the full page.
struct SpendingStatsCard: View {
    let summary: SpendingSummary
    let period: Period

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Spending")
            NavigationLink { SpendingView(period: period) } label: {
                HStack(spacing: 12) {
                    ToonChip(symbol: CostStyle.symbol, color: CostStyle.color, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        if summary.hasMainCurrency {
                            Text(Fmt.money(summary.total, summary.currency)).font(.toon(22, .bold)).monospacedDigit()
                            Text("\(Fmt.money(summary.travel, summary.currency)) getting around · "
                                 + "\(Fmt.money(summary.atDestinations, summary.currency)) at destinations")
                                .font(.toon(12, .bold)).foregroundStyle(Toon.muted).toonLineLimit(2)
                        } else {
                            Text("No costs in \(period.label)").font(.toon(16, .bold))
                            Text("Log fares and other costs from Today or any trip.").font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .black)).foregroundStyle(Toon.muted)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Toon.ink)
                .padding(14)
                .toonCard(radius: 22, shadow: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statsSpending")
        }
    }
}
