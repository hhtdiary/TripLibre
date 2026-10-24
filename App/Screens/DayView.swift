import SwiftUI
import MapKit
import HHTCore

/// One entry in the chronological diary.
enum DiaryItem: Identifiable {
    case visit(Visit, Place?)
    case trip(Trip)
    /// A self-reported stamp no visit accounts for (yet).
    case stamp(Stamp)
    /// A cost on neither a trip nor a visit of the day.
    case cost(Expense)

    var id: String {
        switch self {
        case .visit(let v, _): return "v-" + v.id
        case .trip(let t): return "t-" + t.id
        case .stamp(let s): return "s-" + s.id
        case .cost(let e): return "c-" + e.id
        }
    }
    var start: Date {
        switch self {
        case .visit(let v, _): return v.arrival
        case .trip(let t): return t.departure
        case .stamp(let s): return s.timestamp
        case .cost(let e): return e.timestamp
        }
    }
}

/// Loaded data for one local day.
struct DayData {
    var items: [DiaryItem] = []
    var visits: [Visit] = []
    var trips: [Trip] = []
    var places: [String: Place] = [:]
    /// Stamps attached to each visit, and the ones no visit on screen accounts for.
    var stampsByVisit: [String: [Stamp]] = [:]
    var unmatchedStamps: [Stamp] = []
    /// The day's costs, and the same split by what they're on; `looseCosts` are on nothing shown that day.
    var costs: [Expense] = []
    var costsByTrip: [String: [Expense]] = [:]
    var costsByVisit: [String: [Expense]] = [:]
    var looseCosts: [Expense] = []
    /// Trips and visits with a cost on any day: a stay or trip across midnight is already answered on its other days.
    var paidIDs: Set<String> = []

    static func load(_ store: TravelStore, day: Date) -> DayData {
        let r = DateRange.day(day)
        var d = DayData()
        d.visits = (try? store.visits(overlapping: r.start, r.end)) ?? []
        d.trips = (try? store.trips(overlapping: r.start, r.end)) ?? []
        let ids = Set(d.visits.compactMap(\.placeID) + d.trips.flatMap { [$0.originPlaceID, $0.destinationPlaceID].compactMap { $0 } })
        for id in ids { if let p = try? store.place(id) { d.places[id] = p } }
        let visitIDs = Set(d.visits.map(\.id))
        for s in (try? store.stamps(from: r.start, to: r.end)) ?? [] {
            if let id = s.visitID, visitIDs.contains(id) { d.stampsByVisit[id, default: []].append(s) } else { d.unmatchedStamps.append(s) }
        }
        let tripIDs = Set(d.trips.map(\.id))
        d.costs = (try? store.expenses(from: r.start, to: r.end)) ?? []
        for e in d.costs {
            if let id = e.tripID, tripIDs.contains(id) { d.costsByTrip[id, default: []].append(e) }
            else if let id = e.visitID, visitIDs.contains(id) { d.costsByVisit[id, default: []].append(e) }
            else { d.looseCosts.append(e) }
        }
        d.paidIDs = Set(d.costsByTrip.keys).union(d.costsByVisit.keys)
        // only records reaching past this day can have costs dated on another one
        for t in d.trips where d.costsByTrip[t.id] == nil && (t.departure < r.start || t.arrival > r.end) {
            if !((try? store.expenses(tripID: t.id)) ?? []).isEmpty { d.paidIDs.insert(t.id) }
        }
        for v in d.visits where d.costsByVisit[v.id] == nil && (v.arrival < r.start || (v.departure ?? Date()) > r.end) {
            if !((try? store.expenses(visitID: v.id)) ?? []).isEmpty { d.paidIDs.insert(v.id) }
        }
        d.items = (d.visits.map { DiaryItem.visit($0, $0.placeID.flatMap { d.places[$0] }) } + d.trips.map { DiaryItem.trip($0) }
                   + d.unmatchedStamps.map { DiaryItem.stamp($0) } + d.looseCosts.map { DiaryItem.cost($0) })
            .sorted { $0.start < $1.start }
        return d
    }
}

struct DayView: View {
    @EnvironmentObject var model: AppModel
    @State var day: Date = Calendar.current.startOfDay(for: Calendar.current.date(
        byAdding: .day, value: -UserDefaults.standard.integer(forKey: "hhtDaysAgo"), to: Date())!)
    var fixedDay: Bool = false
    @State private var data = DayData()
    @State private var quickModes: [TravelMode] = [.walk, .bus, .subway, .car]
    @State private var selectedTrip: IDBox?
    @State private var selectedVisit: IDBox?
    @State private var showSettings = false
    @State private var showDatePicker = false
    @State private var reviewCount = 0
    @State private var costTarget: CostSheet?
    @State private var showSpending = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// Raw data past the last stop that falls on this day.
    private var pendingTail: InferenceEngine.UnresolvedTail? {
        guard let t = model.pendingTail else { return nil }
        let r = DateRange.day(day)
        return t.since < r.end && t.lastPoint >= r.start ? t : nil
    }

    var body: some View {
        List {
            if model.isProcessing || model.inferenceFailure != nil {
                Section { InferenceStatusBanner().toonRow(top: 8, bottom: 8) }
            }
            Section {
                MascotSays(text: mascotLine).toonRow(top: 8, bottom: 8)
                if isToday && !fixedDay { StampButton().toonRow(top: 4, bottom: 6) }
                ForEach(costPrompts) { p in
                    CostPromptCard(prompt: p) { costTarget = CostSheet(target: p.target, day: day) }
                        .toonRow(top: 4, bottom: 6)
                }
                if !fixedDay && reviewCount > 0 {
                    reviewBanner
                        .background(NavigationLink { ReviewView() } label: { EmptyView() }.opacity(0))
                        .toonRow()
                }
                DayMap(data: data)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .toonCard(radius: 22, shadow: 5)
                    .toonRow(top: 8, bottom: 10)
                summary.toonRow(top: 8, bottom: 8)
                DaySpendCard(costs: data.costs, isToday: isToday && !fixedDay,
                             onOpen: { showSpending = true }, onAdd: { costTarget = CostSheet(target: .day(day)) })
                    .toonRow(top: 6, bottom: 8)
            }
            Section {
                if data.items.isEmpty && pendingTail == nil {
                    emptyState.toonRow()
                } else {
                    ForEach(data.items) { item in
                        switch item {
                        case .visit(let v, let p):
                            VisitRow(visit: v, place: p, day: day, stamps: data.stampsByVisit[v.id] ?? [],
                                     costs: data.costsByVisit[v.id] ?? []).contentShape(Rectangle())
                                .onTapGesture { selectedVisit = IDBox(id: v.id) }
                                .detailRowAccessibility("visitRow", hint: "Opens the visit to correct it") { selectedVisit = IDBox(id: v.id) }
                                .toonRow(top: 5, bottom: 5)
                        case .trip(let t):
                            TripRow(trip: t, quickModes: quickModes, day: day, costs: data.costsByTrip[t.id] ?? []) { mode in
                                model.perform { try model.edit.setTripMode(t.id, mode) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTrip = IDBox(id: t.id) }
                            .detailRowAccessibility("tripRow", hint: "Opens the trip to correct it") { selectedTrip = IDBox(id: t.id) }
                            .toonRow(top: 3, bottom: 3)
                        case .stamp(let s):
                            StampRow(stamp: s)
                                .swipeActions { Button("Remove", role: .destructive) { model.undoStamp(s) } }
                                .contextMenu { Button("Remove stamp", systemImage: "trash", role: .destructive) { model.undoStamp(s) } }
                                .toonRow(top: 5, bottom: 5)
                        case .cost(let e):
                            CostRow(cost: e)
                                .contentShape(Rectangle())
                                .onTapGesture { costTarget = CostSheet(target: .day(day), existing: e) }
                                .detailRowAccessibility("costRow", hint: "Opens the cost to change it") {
                                    costTarget = CostSheet(target: .day(day), existing: e)
                                }
                                .toonRow(top: 5, bottom: 5)
                        }
                    }
                    if let tail = pendingTail { PendingActivityRow(tail: tail).toonRow(top: 5, bottom: 5) }
                }
            } header: {
                if !data.items.isEmpty || pendingTail != nil { SectionLabel(text: "Your day, step by step") }
            } footer: {
                if isToday { LastInferenceLabel(date: model.lastInferenceAt) }
            }
        }
        .listSectionSpacing(.compact)
        .groupedList()
        .navigationTitle(isToday && !fixedDay ? "Today" : Fmt.shortDay(day))
        .inlineTitle()
        .toolbar {
            if !fixedDay {
                ToolbarItem(placement: .navigation) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous day")
                Button { showDatePicker = true } label: { Image(systemName: "calendar") }.accessibilityLabel("Choose day")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(isToday).accessibilityLabel("Next day")
            }
        }
        .refreshable { await model.runInference() }
        .sheet(item: $selectedTrip) { box in TripDetailView(tripID: box.id).environmentObject(model) }
        .sheet(item: $selectedVisit) { box in VisitDetailView(visitID: box.id).environmentObject(model) }
        .sheet(item: $costTarget) { c in CostEntrySheet(target: c.target, existing: c.existing, day: c.day).environmentObject(model) }
        .navigationDestination(isPresented: $showSpending) { SpendingView(period: .week) }
        .onReceive(model.$route) { r in
            guard let r, r == .settings || r == .stamp, !fixedDay else { return }
            model.route = nil
            if r == .settings { showSettings = true; return }
            // the Stamp widget: back to today, where the confirmation and Undo show, then the same tap as the button
            day = Calendar.current.startOfDay(for: Date())
            showSettings = false
            showDatePicker = false
            selectedTrip = nil
            selectedVisit = nil
            costTarget = nil
            showSpending = false
            model.stampNow()
        }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() }.environmentObject(model) }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDatePicker = false }.confirmTint() } }
            }
            .presentationDetents([.medium])
        }
        .task(id: "\(model.revision)-\(day.timeIntervalSince1970)") { reload() }
        .task(id: isToday) {
            // new fixes arrive without a revision bump; keep the pending tail current while today is on screen
            while isToday && !Task.isCancelled {
                if !model.isProcessing { model.refreshInferenceStatus() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Every finished trip by a usually-paid mode, and every stay at a usually-paid place, with no cost yet and not
    /// waved off: one card each, newest first (issue #75). Only for the last 7 days (like the review banner): later
    /// than that, people rarely remember what they paid.
    private var costPrompts: [CostPrompt] {
        let now = Date()
        guard !fixedDay, now.timeIntervalSince(day) < 7 * 86_400 else { return [] }
        let skipped = Set(model.skippedCostPrompts)
        let trips = data.trips.filter { t in
            t.mode.usuallyPaid && t.arrival <= now && !data.paidIDs.contains(t.id) && !skipped.contains(t.id)
        }
        .map { (end: $0.arrival, prompt: CostPrompt(target: .trip($0), day: day, destination: destinationName($0), id: $0.id)) }
        let visits = data.visits.compactMap { v -> (end: Date, prompt: CostPrompt)? in
            let p = v.placeID.flatMap { data.places[$0] }
            guard p?.category?.usuallyPaid == true, v.arrival <= now, !data.paidIDs.contains(v.id), !skipped.contains(v.id)
            else { return nil }
            return (v.departure ?? now, CostPrompt(target: .visit(v, p), day: day, id: v.id))
        }
        return (trips + visits).sorted { $0.end > $1.end }.map(\.prompt)
    }

    private func destinationName(_ t: Trip) -> String? {
        let pid = t.destinationVisitID.flatMap { id in data.visits.first { $0.id == id }?.placeID } ?? t.destinationPlaceID
        return pid.flatMap { data.places[$0] }.flatMap { $0.isNamed ? $0.displayName : nil }
    }

    private var summary: some View {
        let dist = data.trips.reduce(0) { $0 + $1.distance }
        let time = data.trips.reduce(0) { $0 + $1.duration }
        return StickerGrid {
            StatSticker(value: "\(data.trips.count)", label: "trips", color: Toon.sun, tilt: -2)
            StatSticker(value: Fmt.distance(dist), label: "distance", color: Toon.lime, tilt: 1.5)
            StatSticker(value: Fmt.duration(time), label: "travelling", color: Toon.sky, tilt: 1)
            StatSticker(value: "\(Set(data.visits.compactMap(\.placeID)).count)", label: "places", color: Toon.bubblegum, tilt: -1.5)
        }
        .padding(.vertical, 4)
    }

    private var reviewBanner: some View {
        ToonRowStack {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Toon.ink)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Toon.accent))
            Text("\(reviewCount) trip\(reviewCount == 1 ? "" : "s") in the last 7 days could use a quick check")
                .font(.toon(14, .heavy)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Toon.ink))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Toon.accent).offset(x: 4, y: 4))
    }

    /// What Pip says above the map.
    private var mascotLine: String {
        guard !data.trips.isEmpty else {
            return isToday && !fixedDay ? "No trips yet today. I'm keeping an eye out!" : "A quiet day. Nothing recorded here."
        }
        let dist = Fmt.distance(data.trips.reduce(0) { $0 + $1.distance })
        let n = data.trips.count
        let lead = "\(n) trip\(n == 1 ? "" : "s") and \(dist)\(isToday && !fixedDay ? " so far" : "")."
        var byGroup: [ModeGroup: Double] = [:]
        for t in data.trips { byGroup[t.mode.group, default: 0] += t.duration }
        switch byGroup.max(by: { $0.value < $1.value })?.key {
        case .active: return lead + " Your feet did most of the work!"
        case .transit: return lead + " Transit pro, nice."
        case .car: return lead + " Mostly on wheels today."
        case .longDistance: return lead + " Big journey day!"
        default: return lead
        }
    }

    @ViewBuilder private var emptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            ToonChip(symbol: "moon.zzz", color: Toon.grape, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing recorded for this day yet.").font(.toon(16, .heavy))
                if model.collector.mode == .off {
                    Text("Location collection is off. Turn it on in Settings.").font(.toon(13, .bold)).foregroundStyle(Toon.muted)
                } else if isToday {
                    Text("Visits appear after you've stayed somewhere ~5 minutes; trips once you arrive. Stopping for less? Tap Stamp. Pull to refresh.")
                        .font(.toon(13, .bold)).foregroundStyle(Toon.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Toon.ink)
        .padding(14)
        .toonCard(radius: 20)
    }

    private func shift(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: day), d <= Date() { day = Calendar.current.startOfDay(for: d) }
    }

    private func reload() {
        day = Calendar.current.startOfDay(for: day)
        data = DayData.load(model.store, day: day)
        let freq = (try? model.store.frequentModes(limit: 4)) ?? []
        quickModes = Array((freq + [.walk, .bus, .subway, .car, .bicycle]).reduce(into: [TravelMode]()) { acc, m in
            if !acc.contains(m) { acc.append(m) }
        }.prefix(4))
        reviewCount = (try? model.store.reviewCount(since: Date().addingTimeInterval(-7 * 86_400))) ?? 0
    }
}

// MARK: - Rows

struct VisitRow: View {
    let visit: Visit
    let place: Place?
    let day: Date
    var stamps: [Stamp] = []
    var costs: [Expense] = []

    var body: some View {
        ToonRowStack {
            ToonChip(symbol: place?.category?.symbol ?? "mappin", color: place?.toonColor ?? Toon.stone, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                ToonRowStack(spacing: 6) {
                    Text(place?.isNamed == true ? place!.displayName : (place?.address ?? "Unnamed place"))
                        .font(.toon(18, .bold))
                        .foregroundStyle(place?.isNamed == true ? Toon.ink : Toon.muted)
                        .toonLineLimit(2)
                    if visit.userStatus.isLocked { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Toon.okGreen) }
                    if visit.departure == nil { ToonBadge(text: "here now", color: Toon.accent) }
                    if !stamps.isEmpty {
                        // self-reported, as opposed to purely inferred
                        Label("stamped", systemImage: StampStyle.symbol).labelStyle(.iconOnly)
                            .font(.caption.weight(.bold)).foregroundStyle(Toon.ink)
                            .padding(4).background(Circle().fill(StampStyle.color))
                            .overlay(Circle().strokeBorder(Toon.ink, lineWidth: 1.5))
                            .accessibilityLabel("You stamped this stop")
                    }
                }
                // one Text, so it wraps as a sentence at large text sizes
                Text(meta).monospacedDigit()
                    .font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                if !costs.isEmpty { CostBadge(costs: costs).padding(.top, 2) }
                if let n = visit.notes { Text(n).font(.toon(12, .semibold)).foregroundStyle(Toon.muted).toonLineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .toonCard(radius: 18, shadow: 3)
        }
    }

    private var meta: String {
        var parts = [timeSpan, visit.departure == nil ? "now · \(Fmt.duration(visit.duration()))" : Fmt.duration(visit.duration())]
        if let p = visit.purpose ?? place?.category?.defaultPurpose { parts.append(p.label) }
        return parts.joined(separator: " · ")
    }

    private var timeSpan: String {
        let cal = Calendar.current
        let a = cal.isDate(visit.arrival, inSameDayAs: day) ? Fmt.time(visit.arrival) : "‹ " + Fmt.time(visit.arrival)
        guard let d = visit.departure else { return a + "–" }
        let b = cal.isDate(d, inSameDayAs: day) ? Fmt.time(d) : Fmt.time(d) + " ›"
        return "\(a)–\(b)"
    }
}

struct TripRow: View {
    let trip: Trip
    let quickModes: [TravelMode]
    let day: Date
    var costs: [Expense] = []
    var onQuickMode: (TravelMode) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // dashed "path" between the visit stickers
            Rectangle().fill(.clear).frame(width: 44)
                .overlay {
                    Line().stroke(Toon.ink.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
                        .frame(width: 3)
                }
            VStack(alignment: .leading, spacing: 8) {
                ToonRowStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(Array(uniqueModes.prefix(3).enumerated()), id: \.offset) { _, m in ModeIcon(mode: m, size: 30) }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        ToonRowStack(spacing: 6) {
                            Text(modeText).font(.toon(14, .heavy)).foregroundStyle(Toon.ink)
                            if trip.needsReview { ToonBadge(text: "check") }
                            if trip.hasGap { Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.caption).foregroundStyle(Toon.muted) }
                        }
                        Text("\(Fmt.time(trip.departure))–\(Fmt.time(trip.arrival)) · \(Fmt.duration(trip.duration)) · \(Fmt.distance(trip.distance))")
                            .font(.toon(12, .bold)).monospacedDigit().foregroundStyle(Toon.muted)
                        if !costs.isEmpty { CostBadge(costs: costs).padding(.top, 2) }
                    }
                }
                if trip.needsReview {
                    Text("Did I get that right?").font(.toon(13, .heavy)).foregroundStyle(Toon.ink)
                    // full labels when they fit, icons only on narrow screens, one per line at large text sizes
                    ViewThatFits(in: .horizontal) {
                        quickButtons(iconOnly: false)
                        quickButtons(iconOnly: true)
                        quickButtons(iconOnly: false, stacked: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(trip.needsReview ? 12 : 4)
            .background {
                if trip.needsReview { Color.clear.toonCard(Toon.cream, radius: 18, shadow: 0, dashed: true) }
            }
        }
    }

    private func quickButtons(iconOnly: Bool, stacked: Bool = false) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            ForEach(quickModes.filter { $0 != trip.mode }.prefix(3)) { m in
                Button { onQuickMode(m) } label: {
                    if iconOnly {
                        Image(systemName: m.symbol).accessibilityLabel(m.label)
                    } else {
                        Label(m.label, systemImage: m.symbol).labelStyle(.titleAndIcon)
                            .lineLimit(1).fixedSize()
                    }
                }
                .buttonStyle(ToonButtonStyle(height: 34, fontSize: 12, shadow: 2))
            }
            if trip.modeAuto != nil && trip.modeAuto != .unknown {
                Button { onQuickMode(trip.mode) } label: { Image(systemName: "checkmark").fontWeight(.black) }
                    .buttonStyle(ToonButtonStyle(fill: Toon.lime, height: 34, fontSize: 13, shadow: 2))
                    .accessibilityLabel("Confirm \(trip.mode.label)")
            }
        }
        .padding(.trailing, 2)
    }

    private var uniqueModes: [TravelMode] { trip.displayModes }

    private var modeText: String { trip.displayModes.map(\.label).joined(separator: " + ") }
}

extension View {
    /// Diary rows open their detail sheet on tap. VoiceOver reads the row as one button (its own buttons, like the
    /// quick mode picks, become actions on it) and activating it opens the same sheet.
    func detailRowAccessibility(_ identifier: String, hint: String, open: @escaping () -> Void) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint)
            .accessibilityAction { open() }
            .accessibilityIdentifier(identifier)
    }
}

/// Vertical line used for the dashed path between diary stickers.
struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

// MARK: - Stamps

enum StampStyle {
    static let symbol = "hand.tap.fill"
    static let color = Toon.sun
}

/// "Stamp this moment": one tap, no form. Confirms with the time and an Undo for a few seconds.
struct StampButton: View {
    @EnvironmentObject var model: AppModel
    @State private var stamped = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.stampNow()
                stamped += 1
            } label: {
                Label("Stamp this moment", systemImage: StampStyle.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ToonButtonStyle(fill: StampStyle.color, height: 46, fontSize: 16, shadow: 3))
            .accessibilityHint("Records that you stopped somewhere around here, around now")
            .sensoryFeedback(.success, trigger: stamped)

            if let s = model.lastStamp {
                HStack(spacing: 8) {
                    Text(model.lastStampRepeated ? "Already stamped at \(Fmt.time(s.timestamp)), so I kept just one."
                         : "Stamped at \(Fmt.time(s.timestamp)). I'll fit it into your day.")
                        .font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                    Spacer(minLength: 0)
                    Button("Undo") { model.undoStamp(s) }
                        .buttonStyle(.borderless)   // in a List row, only this button reacts to its tap
                        .font(.toon(12, .heavy)).foregroundStyle(Toon.accentDeep)
                }
                .task(id: s.id) {
                    // cancelled when the view goes away (e.g. a Stamp widget tap rebuilds Today): leave it for the new one
                    do { try await Task.sleep(for: .seconds(6)) } catch { return }
                    if model.lastStamp?.id == s.id { model.dismissStampConfirmation() }
                }
            }
        }
    }
}

/// A stamp no visit accounts for: kept as the user's own record, clearly not an inferred stop.
struct StampRow: View {
    let stamp: Stamp

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ToonChip(symbol: StampStyle.symbol, color: StampStyle.color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("You stamped a stop").font(.toon(16, .bold)).foregroundStyle(Toon.ink)
                    ToonBadge(text: "self-reported", color: Toon.cream)
                }
                Text(detail).font(.toon(12, .bold)).monospacedDigit().foregroundStyle(Toon.muted)
                Text("Not matched to a visit yet. It will be once there's location data around it.")
                    .font(.toon(12, .semibold)).foregroundStyle(Toon.muted).fixedSize(horizontal: false, vertical: true)
                if let n = stamp.note { Text(n).font(.toon(12, .semibold)).foregroundStyle(Toon.muted).toonLineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .toonCard(Toon.cream, radius: 18, shadow: 0, dashed: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let t = Fmt.time(stamp.timestamp, tz: stamp.timeZone)
        guard stamp.coordinate != nil, let u = stamp.uncertainty else { return "\(t) · no location" }
        return "\(t) · within ~\(Fmt.distance(u))"
    }
}

// MARK: - Map

struct DayMap: View {
    let data: DayData
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(data.trips) { t in
                if t.segments.count > 1 {
                    ForEach(t.segments) { s in
                        if let poly = s.routePolyline {
                            let coords = Polyline.decode(poly).map(\.cl)
                            MapPolyline(coordinates: coords)
                                .stroke(Toon.ink, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                            MapPolyline(coordinates: coords)
                                .stroke(s.mode.color, style: ToonMap.style(for: s.mode))
                        }
                    }
                } else if t.route.count >= 2 {
                    MapPolyline(coordinates: t.route.map(\.cl))
                        .stroke(Toon.ink, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: t.route.map(\.cl))
                        .stroke(t.mode.color, style: ToonMap.style(for: t.mode))
                }
            }
            ForEach(data.unmatchedStamps.filter { $0.coordinate != nil }) { s in
                Annotation("", coordinate: s.coordinate!.cl, anchor: .center) {
                    ToonPin(symbol: StampStyle.symbol, color: StampStyle.color, size: 22)
                }
            }
            ForEach(data.visits) { v in
                let p = v.placeID.flatMap { data.places[$0] }
                Annotation("", coordinate: (p?.coordinate ?? v.coordinate).cl, anchor: .center) {
                    ToonPin(symbol: p?.category?.symbol ?? "mappin", color: p?.category?.toonColor ?? Toon.accent,
                            label: p?.isNamed == true ? p!.displayName : nil)
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .onAppear { position = Self.camera(for: data) }
        .onChange(of: data.items.map(\.id)) { _, _ in position = Self.camera(for: data) }
    }

    /// Fit everything, but never closer than ~1 km across (a lone visit would otherwise zoom to street level).
    static func camera(for data: DayData) -> MapCameraPosition {
        let coords = data.visits.map { v in (v.placeID.flatMap { data.places[$0] }?.coordinate ?? v.coordinate) }
            + data.trips.flatMap(\.route) + data.unmatchedStamps.compactMap(\.coordinate)
        guard let first = coords.first else { return .automatic }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.3),
                                    longitudeDelta: max(0.012, (maxLon - minLon) * 1.3))
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Cartoon map pieces

enum ToonMap {
    /// Walking is drawn dotted, rail/transit dashed, everything else solid — on top of an ink casing.
    static func style(for mode: TravelMode) -> StrokeStyle {
        switch mode.group {
        case .active: return StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [1, 7])
        case .transit, .longDistance: return StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [9, 5])
        default: return StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
        }
    }
}

/// Sticker-style map pin: coloured disc with an icon and an optional name tag underneath.
struct ToonPin: View {
    let symbol: String
    let color: Color
    var label: String?
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(Toon.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(Toon.ink, lineWidth: 2.5))
            .background(Circle().fill(Toon.ink).offset(x: 1.5, y: 2))
            .overlay(alignment: .top) {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.toon(11, .heavy)).foregroundStyle(Toon.ink)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Toon.paper))
                        .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: 2))
                        .offset(y: size + 3)
                }
            }
    }
}

// MARK: - Inference status

/// Shown while the diary is being rebuilt from raw data, or when the last rebuild failed.
/// Nothing at all when inference is idle and healthy.
struct InferenceStatusBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.isProcessing {
            running.padding(.horizontal, 12).padding(.vertical, 8).toonCard(Toon.cream, radius: 18, shadow: 3)
        } else if let f = model.inferenceFailure {
            failed(f).padding(.horizontal, 12).padding(.vertical, 8).toonCard(Color(hex: 0xFFE3DC), radius: 18, shadow: 3)
        }
    }

    private var running: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("Updating your diary…").font(.subheadline.weight(.semibold))
                Text(phaseText).font(.caption).foregroundStyle(Toon.muted).monospacedDigit()
                if let p = model.progress, p.phase == .resolvingVisits, p.staysTotal > 1 {
                    ProgressView(value: Double(p.staysResolved), total: Double(p.staysTotal))
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(detailText(now: ctx.date)).font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func failed(_ f: AppModel.InferenceFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Couldn't update your diary", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
            Text("Your recorded data is safe; the diary just hasn't caught up with it. \(f.at, format: .relative(presentation: .named)).")
                .font(.caption).foregroundStyle(Toon.muted)
            Text(f.message).font(.caption2.monospaced()).foregroundStyle(Toon.muted).toonLineLimit(3).textSelection(.enabled)
            Button { Task { await model.runInference() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                .buttonStyle(ToonButtonStyle(height: 34, fontSize: 12, shadow: 2))
        }
        .padding(.vertical, 4)
    }

    private var phaseText: String {
        let points = model.progress.map { " · \($0.report.pointsConsidered.formatted()) points" } ?? ""
        switch model.phase {
        case .syncingMotion, nil: return "Syncing motion activity"
        case .engine(.loadingPoints): return "Loading location points"
        case .engine(.detectingStays): return "Detecting stays" + points
        case .engine(.resolvingVisits):
            let p = model.progress
            return "Matching visits" + (p.map { $0.staysTotal > 0 ? " (\($0.staysResolved) of \($0.staysTotal))" : "" } ?? "") + points
        case .engine(.buildingTrips): return "Building trips" + points
        case .engine(.finalizing): return "Saving"
        }
    }

    private func detailText(now: Date) -> String {
        var parts: [String] = []
        if let r = model.progress?.report {
            let visits = r.visitsCreated + r.visitsUpdated
            if visits > 0 { parts.append("\(visits) visit\(visits == 1 ? "" : "s") so far") }
            if r.tripsCreated > 0 { parts.append("\(r.tripsCreated) trip\(r.tripsCreated == 1 ? "" : "s")") }
        }
        if let s = model.runStartedAt {
            let e = Int(max(0, now.timeIntervalSince(s)))
            parts.append(String(format: "%d:%02d elapsed", e / 60, e % 60))
        }
        if model.rerunRequested { parts.append("another update queued") }
        return parts.joined(separator: " · ")
    }
}

/// The end of the timeline when raw data exists past the last stop that no run has turned into a visit or trip yet.
struct PendingActivityRow: View {
    @EnvironmentObject var model: AppModel
    let tail: InferenceEngine.UnresolvedTail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.isProcessing ? "hourglass" : "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
            VStack(alignment: .leading, spacing: 2) {
                Text("Not in your diary yet").font(.subheadline.weight(.medium))
                Text("Since \(Fmt.time(tail.since)) · \(tail.pointCount.formatted()) points · last fix \(Fmt.time(tail.lastPoint))")
                    .font(.caption).monospacedDigit().foregroundStyle(Toon.muted)
                Text(model.isProcessing ? "Being processed now…"
                     : "Recorded, not lost. It becomes a trip once you've stopped somewhere for ~5 minutes.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !model.isProcessing {
                Button("Update") { Task { await model.runInference() } }
                    .buttonStyle(ToonButtonStyle(fill: Toon.accent, height: 34, fontSize: 12, shadow: 2))
            }
        }
        .padding(12)
        .toonCard(Toon.cream, radius: 18, shadow: 0, dashed: true)
    }
}

/// "Diary updated 5 minutes ago", ticking.
struct LastInferenceLabel: View {
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            if let d = date {
                Text("Diary updated \(d, format: .relative(presentation: .named))")
            } else {
                Text("Diary not built yet")
            }
        }
        .font(.caption2).foregroundStyle(Toon.muted)
    }
}
