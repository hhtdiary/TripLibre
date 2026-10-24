import SwiftUI
import HHTCore

struct DaySummary: Identifiable {
    var id: Date { day }
    var day: Date
    var trips = 0
    var distance = 0.0
    var modes: [TravelMode] = []
    var places: [String] = []
    var needsReview = 0
    var flight = false
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var months: [(month: Date, days: [DaySummary])] = []
    @State private var flightsCount = 0
    @State private var weekOffset = 0

    var body: some View {
        List {
            if model.isProcessing || model.inferenceFailure != nil {
                Section { InferenceStatusBanner().toonRow(top: 8, bottom: 8) }
            }
            Section {
                WeekChart(days: months.flatMap(\.days), offset: $weekOffset).toonRow(top: 8, bottom: 10)
            }
            Section {
                shortcut("line.3.horizontal.decrease.circle", Toon.paper, "Find trips…", tilt: -1) { TripSearchView() }
                shortcut("airplane", Toon.aqua, "Flights", count: flightsCount, tilt: 1) { FlightsView() }
                shortcut("calendar.badge.clock", Toon.bubblegum, "Life phases", tilt: -0.5) { LifePhasesView() }
            }
            ForEach(months, id: \.month) { m in
                Section {
                    ForEach(m.days) { d in
                        DayRow(summary: d)
                            .background(NavigationLink { DayView(day: d.day, fixedDay: true) } label: { EmptyView() }.opacity(0))
                            .toonRow(top: 7, bottom: 7)
                    }
                } header: {
                    Text(monthTitle(m.month))
                        .font(.toon(16, .bold)).foregroundStyle(.white).textCase(nil)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Toon.ink))
                        .tilt(-2)
                        .padding(.vertical, 4)
                        .toonSectionText()
                }
            }
            if months.isEmpty {
                HStack(spacing: 12) {
                    Mascot(size: 44)
                    Text("No trips yet. Your history will build up here day by day.")
                        .font(.toon(14, .bold)).foregroundStyle(Toon.muted)
                }
                .toonRow()
            }
        }
        .listSectionSpacing(.compact)
        .groupedList()
        .navigationTitle("Timeline")
        .task(id: model.revision) { load() }
    }

    private func shortcut<D: View>(_ symbol: String, _ color: Color, _ title: String, count: Int = 0, tilt: Double,
                                   @ViewBuilder destination: @escaping () -> D) -> some View {
        HStack(spacing: 12) {
            ToonChip(symbol: symbol, color: color, size: 36)
            Text(title).font(.toon(16, .heavy)).foregroundStyle(Toon.ink)
            Spacer()
            if count > 0 {
                Text("\(count)").font(.toon(12, .black)).foregroundStyle(.white)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Capsule().fill(Toon.ink))
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).foregroundStyle(Toon.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .toonCard(radius: 18, shadow: 3)
        .tilt(tilt)
        .background(NavigationLink { destination() } label: { EmptyView() }.opacity(0))
        .toonRow(top: 6, bottom: 6)
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }

    private func load() {
        let cal = Calendar.current
        let trips = (try? model.store.allTrips(withSegments: true)) ?? []
        let visits = (try? model.store.allVisits()) ?? []
        let places = Dictionary(uniqueKeysWithValues: ((try? model.store.places()) ?? []).map { ($0.id, $0) })
        let visitPlace = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0.placeID) })
        var days: [Date: DaySummary] = [:]
        for t in trips {
            let d = cal.startOfDay(for: t.departure)
            var s = days[d] ?? DaySummary(day: d)
            s.trips += 1
            s.distance += t.distance
            if !s.modes.contains(t.mode) { s.modes.append(t.mode) }
            if t.needsReview { s.needsReview += 1 }
            if t.mode == .airplane { s.flight = true }
            let dest = (t.destinationVisitID.flatMap { visitPlace[$0] ?? nil } ?? t.destinationPlaceID).flatMap { places[$0] }
            if let name = dest?.isNamed == true ? dest?.displayName : nil, !s.places.contains(name) { s.places.append(name) }
            days[d] = s
        }
        for v in visits {
            let d = cal.startOfDay(for: v.arrival)
            if days[d] == nil { days[d] = DaySummary(day: d) }
            if let p = v.placeID.flatMap({ places[$0] }), p.isNamed, !(days[d]!.places.contains(p.displayName)) {
                days[d]!.places.append(p.displayName)
            }
        }
        let grouped = Dictionary(grouping: days.values) { cal.date(from: cal.dateComponents([.year, .month], from: $0.day))! }
        months = grouped.map { (month: $0.key, days: $0.value.sorted { $0.day > $1.day }) }.sorted { $0.month > $1.month }
        flightsCount = ((try? model.store.flights()) ?? []).count
    }
}

/// "This week" sticker: one chunky bar per day, flip back through earlier weeks.
struct WeekChart: View {
    let days: [DaySummary]
    @Binding var offset: Int   // 0 = this week, -1 = last week…

    private var cal: Calendar { Calendar.current }

    private var week: [(day: Date, summary: DaySummary?)] {
        let ref = cal.date(byAdding: .weekOfYear, value: offset, to: Date())!
        let start = cal.dateInterval(of: .weekOfYear, for: ref)!.start
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return (d, byDay[d])
        }
    }

    private var title: String {
        switch offset {
        case 0: return "This week"
        case -1: return "Last week"
        default:
            let w = week
            return "\(w.first!.day.formatted(.dateTime.month(.abbreviated).day())) – \(w.last!.day.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    /// ‹ This week ›, or both arrows above the title when they don't fit on one line.
    private var weekNavigation: some View {
        let title = Text(title).font(.toon(18, .bold)).foregroundStyle(Toon.ink)
        let previous = Button { withAnimation(.spring(duration: 0.4, bounce: 0.35)) { offset -= 1 } } label: {
            Image(systemName: "chevron.left").fontWeight(.black)
        }
        .buttonStyle(ToonButtonStyle(height: 30, fontSize: 12, shadow: 2))
        .accessibilityLabel("Previous week")
        let next = Button { withAnimation(.spring(duration: 0.4, bounce: 0.35)) { offset += 1 } } label: {
            Image(systemName: "chevron.right").fontWeight(.black)
        }
        .buttonStyle(ToonButtonStyle(fill: offset < 0 ? Toon.paper : Toon.stone, height: 30, fontSize: 12, shadow: offset < 0 ? 2 : 0))
        .disabled(offset >= 0)
        .accessibilityLabel("Next week")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { previous; title.lineLimit(1); next }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { previous; next }
                title
            }
        }
    }

    var body: some View {
        let w = week
        let trips = w.reduce(0) { $0 + ($1.summary?.trips ?? 0) }
        let dist = w.reduce(0.0) { $0 + ($1.summary?.distance ?? 0) }
        let peak = max(1, w.map { $0.summary?.trips ?? 0 }.max() ?? 1)
        let busiest = w.filter { ($0.summary?.trips ?? 0) > 0 }.max { ($0.summary?.trips ?? 0) < ($1.summary?.trips ?? 0) }

        let totals = Text("\(trips) trip\(trips == 1 ? "" : "s") · \(Fmt.distance(dist))")
            .font(.toon(13, .heavy)).foregroundStyle(Toon.muted)

        VStack(alignment: .leading, spacing: 10) {
            // the week's totals move under the title when they don't fit beside it
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    weekNavigation
                    Spacer(minLength: 4)
                    totals.lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    weekNavigation
                    totals
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(w, id: \.day) { d in
                    let n = d.summary?.trips ?? 0
                    let today = cal.isDateInToday(d.day)
                    let future = d.day > Date()
                    VStack(spacing: 4) {
                        Text(n > 0 ? "\(n)" : " ").font(.toon(11, .black)).foregroundStyle(Toon.ink)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(today ? Toon.accent : (n == 0 ? Toon.paper : Toon.sky))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Toon.ink.opacity(future ? 0.3 : 1),
                                              style: StrokeStyle(lineWidth: Toon.line, dash: future ? [4, 4] : [])))
                            .frame(height: 12 + 64 * CGFloat(n) / CGFloat(peak))
                        Text(d.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.toon(12, .black)).foregroundStyle(today ? Toon.accentDeep : Toon.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d.day.formatted(.dateTime.weekday(.wide))): \(n) trips")
                }
            }
            .frame(minHeight: 112, alignment: .bottom)
            if let b = busiest {
                Text("Busiest day: \(b.day.formatted(.dateTime.weekday(.wide))), \(b.summary!.trips) trips")
                    .font(.toon(12, .heavy)).foregroundStyle(Toon.muted)
            } else {
                Text(offset == 0 ? "A fresh week. Where to first?" : "A quiet week, no trips recorded.")
                    .font(.toon(12, .heavy)).foregroundStyle(Toon.muted)
            }
        }
        .padding(14)
        .toonCard(radius: 22, shadow: 4)
    }
}

struct DayRow: View {
    let summary: DaySummary

    private var isToday: Bool { Calendar.current.isDateInToday(summary.day) }

    var body: some View {
        ToonRowStack {
            VStack(spacing: 0) {
                Text(summary.day.formatted(.dateTime.day())).font(.toon(24, .bold)).monospacedDigit()
                Text(summary.day.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.toon(11, .black))
            }
            .foregroundStyle(Toon.ink)
            .frame(minWidth: 54, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isToday ? Toon.accent : Toon.cream))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Toon.ink, lineWidth: Toon.line))
            VStack(alignment: .leading, spacing: 6) {
                ToonRowStack(spacing: 6) {
                    if summary.flight { Image(systemName: "airplane").font(.system(size: 13, weight: .bold)).foregroundStyle(Toon.ink) }
                    Text(summary.places.isEmpty ? Fmt.shortDay(summary.day) : summary.places.prefix(4).joined(separator: " → "))
                        .font(.toon(14, .heavy)).foregroundStyle(Toon.ink).toonLineLimit(2)
                    Spacer(minLength: 0)
                    if summary.needsReview > 0 { ToonBadge(text: "\(summary.needsReview) to check") }
                }
                ToonRowStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(summary.modes.prefix(4)) { m in ModeIcon(mode: m, size: 24) }
                    }
                    Text("\(summary.trips) trips · \(Fmt.distance(summary.distance))")
                        .font(.toon(12, .bold)).foregroundStyle(Toon.muted).toonLineLimit(1, minScale: 0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .toonCard(radius: 20, shadow: 4)
    }
}

/// Simple filter-based query over the trip table (brief §15).
struct TripSearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: TravelMode?
    @State private var placeID: String?
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var to = Date()
    @State private var afterHour = 0
    @State private var weekendsOnly = false
    @State private var places: [Place] = []
    @State private var results: [Trip] = []
    @State private var names: [String: String] = [:]
    @State private var selected: IDBox?

    var body: some View {
        List {
            Section {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, displayedComponents: .date)
                Picker("Mode", selection: $mode) {
                    Text("Any").tag(TravelMode?.none)
                    ForEach(TravelMode.allCases) { m in Text(m.label).tag(TravelMode?.some(m)) }
                }
                Picker("Origin or destination", selection: $placeID) {
                    Text("Any").tag(String?.none)
                    ForEach(places) { p in Text(p.displayName).tag(String?.some(p.id)) }
                }
                Stepper("Departing after \(afterHour):00", value: $afterHour, in: 0...23)
                Toggle("Weekends only", isOn: $weekendsOnly)
            } header: { Text("Filters").toonSectionText() }
            Section {
                ForEach(results) { t in
                    Button { selected = IDBox(id: t.id) } label: {
                        HStack {
                            ModeIcon(mode: t.mode, size: 24)
                            VStack(alignment: .leading) {
                                Text("\(names[t.id] ?? "")").font(.subheadline).foregroundStyle(.primary)
                                Text("\(Fmt.shortDay(t.departure)) \(Fmt.time(t.departure)) · \(Fmt.distance(t.distance)) · \(Fmt.duration(t.duration))")
                                    .font(.caption).foregroundStyle(Toon.muted)
                            }
                        }
                    }
                }
            } header: { Text("\(results.count) trips · \(Fmt.distance(results.reduce(0) { $0 + $1.distance }))").toonSectionText() }
        }
        .toonBackground()
        .navigationTitle("Find trips")
        .inlineTitle()
        .sheet(item: $selected) { b in TripDetailView(tripID: b.id).environmentObject(model) }
        .task { places = ((try? model.store.places()) ?? []).filter(\.isNamed) }
        .task(id: "\(mode?.rawValue ?? "")\(placeID ?? "")\(from)\(to)\(afterHour)\(weekendsOnly)\(model.revision)") { search() }
    }

    private func search() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
        var trips = ((try? model.store.trips(overlapping: start, end, withSegments: false)) ?? []).filter { $0.departure >= start && $0.departure < end }
        if let mode { trips = trips.filter { $0.mode == mode } }
        if afterHour > 0 { trips = trips.filter { cal.component(.hour, from: $0.departure) >= afterHour } }
        if weekendsOnly { trips = trips.filter { cal.isDateInWeekend($0.departure) } }
        var n: [String: String] = [:]
        var keep: [Trip] = []
        for t in trips {
            let o = (t.originVisitID.flatMap { try? model.store.visit($0) }?.placeID ?? t.originPlaceID)
            let d = (t.destinationVisitID.flatMap { try? model.store.visit($0) }?.placeID ?? t.destinationPlaceID)
            if let placeID, o != placeID && d != placeID { continue }
            let on = o.flatMap { try? model.store.place($0) }?.displayName ?? "?"
            let dn = d.flatMap { try? model.store.place($0) }?.displayName ?? "?"
            n[t.id] = "\(on) → \(dn)"
            keep.append(t)
        }
        names = n
        results = keep.reversed()
    }
}
