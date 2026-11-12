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
    /// The day map's trip lines: schematic origin→destination curves, never raw GPS (issue #109).
    var connections: [SchematicTrips.Connection] = []
    var places: [String: Place] = [:]
    /// The day's visits plus trip ends that fall on another day, by id (for trip endpoints).
    var visitsByID: [String: Visit] = [:]
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
        for v in d.visits { d.visitsByID[v.id] = v }
        // a trip across midnight starts or ends at a stop on the neighbouring day
        for id in Set(d.trips.flatMap { [$0.originVisitID, $0.destinationVisitID].compactMap { $0 } }) where d.visitsByID[id] == nil {
            if let v = try? store.visit(id) { d.visitsByID[id] = v }
        }
        let ids = Set(d.visitsByID.values.compactMap(\.placeID) + d.trips.flatMap { [$0.originPlaceID, $0.destinationPlaceID].compactMap { $0 } })
        for id in ids { if let p = try? store.place(id) { d.places[id] = p } }
        d.connections = SchematicTrips.layout(d.trips.sorted { $0.departure < $1.departure }
            .map { SchematicTrips.leg(for: $0, visits: d.visitsByID, places: d.places) })
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
    @State private var placeReviews: [PlaceReview] = []
    @State private var showPlaceReviews = false
    @AppStorage("placeRecallRadius") private var recallRadius = PlaceRecall.defaultRadius
    /// The one-line "tap a stop, tap a trip" tip above the rows, until it's waved off or the tutorial is opened from it.
    @AppStorage("diaryTipDismissed") private var tipDismissed = false
    @State private var showTutorial = false

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
                // one place to confirm at a time; the rest behind "More to check" (issue #116)
                if let r = placeReviews.first {
                    PlaceReviewCard(review: r, more: placeReviews.count - 1) { showPlaceReviews = true }
                        .toonRow(top: 4, bottom: 6)
                }
                ForEach(costPrompts) { p in
                    CostPromptCard(prompt: p) { costTarget = CostSheet(target: p.target, day: day) }
                        .toonRow(top: 4, bottom: 6)
                }
                if !fixedDay && reviewCount > 0 {
                    reviewBanner
                        .background(NavigationLink { ReviewView() } label: { EmptyView() }.opacity(0))
                        .toonRow()
                }
                DayMap(data: data) { selectedTrip = IDBox(id: $0) }
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
                    if !fixedDay && !tipDismissed && !data.items.isEmpty {
                        DiaryTipCard(onShow: { showTutorial = true }, onDismiss: { tipDismissed = true })
                            .toonRow(top: 5, bottom: 5)
                    }
                    ForEach(data.items) { item in
                        switch item {
                        case .visit(let v, let p):
                            VisitRow(visit: v, place: p, day: day, stamps: data.stampsByVisit[v.id] ?? [],
                                     costs: data.costsByVisit[v.id] ?? [])
                                .detailRow("visitRow", hint: "Opens the visit to correct it") { selectedVisit = IDBox(id: v.id) }
                                .toonRow(top: 5, bottom: 5)
                        case .trip(let t):
                            TripRow(trip: t, quickModes: quickModes, day: day, costs: data.costsByTrip[t.id] ?? []) { mode in
                                model.perform { try model.edit.setTripMode(t.id, mode) }
                            }
                            .detailRow("tripRow", hint: "Opens the trip to correct it") { selectedTrip = IDBox(id: t.id) }
                            .toonRow(top: 3, bottom: 3)
                        case .stamp(let s):
                            StampRow(stamp: s)
                                .swipeActions { Button("Remove", role: .destructive) { model.undoStamp(s) } } // a11y-check:disable duplicate-button-label (a row action: VoiceOver offers it on its own row)
                                .contextMenu { Button("Remove stamp", systemImage: "trash", role: .destructive) { model.undoStamp(s) } } // a11y-check:disable sheet-focus-return, duplicate-button-label (a row action: VoiceOver offers it on its own row)
                                .toonRow(top: 5, bottom: 5)
                        case .cost(let e):
                            CostRow(cost: e)
                                .detailRow("costRow", hint: "Opens the cost to change it") {
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
        .navigationTitle(isToday && !fixedDay ? L("Today") : Fmt.shortDay(day))
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
        .sheet(isPresented: $showPlaceReviews) { PlaceReviewList(reviews: placeReviews).environmentObject(model) }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView {
                showTutorial = false
                tipDismissed = true
            }
        }
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
            showPlaceReviews = false
            showTutorial = false
            model.stampNow()
        }
        // SettingsView sets its own title
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() }.environmentObject(model) } // a11y-check:disable missing-navigation-title
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Choose a day")
                    .inlineTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDatePicker = false }.confirmTint() } }
            }
            .presentationDetents([.medium])
        }
        // the recall radius too: Settings changes it without an edit, and the place reviews depend on it
        .task(id: "\(model.revision)-\(day.timeIntervalSince1970)-\(recallRadius)") { reload() }
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
            StatSticker(value: data.trips.count.formatted(), label: "trips", color: Toon.sun, tilt: -2)
            StatSticker(value: Fmt.distance(dist), label: "distance", color: Toon.lime, tilt: 1.5)
            StatSticker(value: Fmt.duration(time), label: "travelling", color: Toon.sky, tilt: 1)
            StatSticker(value: Set(data.visits.compactMap(\.placeID)).count.formatted(), label: "places", color: Toon.bubblegum, tilt: -1.5)
        }
        .padding(.vertical, 4)
    }

    private var reviewBanner: some View {
        ToonRowStack {
            // the icons stay as they are (fixed, not hidden): when they change, Apple's audit reports the banner text as
            // only partly scaling
            // swiftlint:disable:next accessibility_label_for_image
            Image(systemName: "checklist") // a11y-check:disable image-missing-label
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Toon.ink) // a11y-check:disable fixed-font-size
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Toon.accent))
            Text(L("%lld trips in the last 7 days could use a quick check", reviewCount))
                .font(.toon(14, .heavy)).foregroundStyle(.white) // a11y-check:disable hardcoded-color (on Toon.ink in both modes)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // swiftlint:disable:next accessibility_label_for_image
            Image(systemName: "arrow.right").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white) // a11y-check:disable hardcoded-color, fixed-font-size, image-missing-label
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Toon.ink))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Toon.accent).offset(x: 4, y: 4))
    }

    /// What Pip says above the map.
    private var mascotLine: String {
        guard !data.trips.isEmpty else {
            return isToday && !fixedDay ? L("No trips yet today. I'm keeping an eye out!") : L("A quiet day. Nothing recorded here.")
        }
        let dist = Fmt.distance(data.trips.reduce(0) { $0 + $1.distance })
        let n = data.trips.count
        let lead = isToday && !fixedDay ? L("%@ and %@ so far.", L("%lld trips", n), dist) : L("%@ and %@.", L("%lld trips", n), dist)
        var byGroup: [ModeGroup: Double] = [:]
        for t in data.trips { byGroup[t.mode.group, default: 0] += t.duration }
        switch byGroup.max(by: { $0.value < $1.value })?.key {
        case .active: return lead + " " + L("Your feet did most of the work!")
        case .transit: return lead + " " + L("Transit pro, nice.")
        case .car: return lead + " " + L("Mostly on wheels today.")
        case .longDistance: return lead + " " + L("Big journey day!")
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
        // like the cost prompts: Today and the last 7 days only, while the stop is still remembered
        placeReviews = fixedDay || Date().timeIntervalSince(day) >= 7 * 86_400 ? []
            : PlaceReview.load(model.store, visits: data.visits, places: data.places, radius: recallRadius,
                               skipped: Set(model.skippedPlaceReviews))
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
            ToonChip(symbol: place?.category?.symbol ?? "mappin", color: place?.toonColor ?? Toon.stone, size: 44, label: place?.category?.localizedLabel)
            VStack(alignment: .leading, spacing: 2) {
                ToonRowStack(spacing: 6) {
                    Text(place.flatMap { $0.isNamed ? $0.displayName : nil } ?? place?.address ?? L("Unnamed place"))
                        .font(.toon(18, .bold))
                        .foregroundStyle(place?.isNamed == true ? Toon.ink : Toon.muted)
                        .toonLineLimit(2)
                    if visit.userStatus.isLocked { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Toon.okGreen).accessibilityLabel("Confirmed") }
                    if visit.departure == nil { ToonBadge(text: "here now", color: Toon.accent) }
                    if !stamps.isEmpty {
                        // self-reported, as opposed to purely inferred
                        Label("You stamped this stop", systemImage: StampStyle.symbol).labelStyle(.iconOnly)
                            .font(.caption.weight(.bold)).foregroundStyle(Toon.ink)
                            .padding(4).background(Circle().fill(StampStyle.color))
                            .overlay(Circle().strokeBorder(Toon.ink, lineWidth: 1.5))
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
        var parts = [timeSpan, visit.departure == nil ? L("now · %@", Fmt.duration(visit.duration())) : Fmt.duration(visit.duration())]
        if let p = visit.purpose ?? place?.category?.defaultPurpose { parts.append(p.localizedLabel) }
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
                            if trip.hasGap { Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.caption).foregroundStyle(Toon.muted).accessibilityLabel("Gap in the recording") }
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
                        Image(systemName: m.symbol).accessibilityLabel(m.localizedLabel)
                    } else {
                        Label(m.localizedLabel, systemImage: m.symbol).labelStyle(.titleAndIcon)
                            .fixedSize()
                    }
                }
                .buttonStyle(ToonButtonStyle(height: 34, fontSize: 12, shadow: 2))
            }
            if trip.modeAuto != nil && trip.modeAuto != .unknown {
                Button { onQuickMode(trip.mode) } label: { Image(systemName: "checkmark").fontWeight(.black) }
                    .buttonStyle(ToonButtonStyle(fill: Toon.lime, height: 34, fontSize: 13, shadow: 2))
                    .accessibilityLabel(L("Confirm %@", trip.mode.localizedLabel))
            }
        }
        .padding(.trailing, 2)
    }

    private var uniqueModes: [TravelMode] { trip.displayModes }

    private var modeText: String { trip.displayModes.map(\.localizedLabel).joined(separator: " + ") }
}

extension View {
    /// Diary rows open their detail sheet on tap. VoiceOver reads the row as one button (its own buttons, like the
    /// quick mode picks, become actions on it) and activating it opens the same sheet.
    func detailRow(_ identifier: String, hint: LocalizedStringKey, open: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture { open() }
            .accessibilityElement(children: .combine)
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
                    Text(model.lastStampRepeated ? L("Already stamped at %@, so I kept just one.", Fmt.time(s.timestamp))
                         : L("Stamped at %@. I'll fit it into your day.", Fmt.time(s.timestamp)))
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
        guard stamp.coordinate != nil, let u = stamp.uncertainty else { return L("%@ · no location", t) }
        return L("%@ · within ~%@", t, Fmt.distance(u))
    }
}

// MARK: - Map

struct DayMap: View {
    let data: DayData
    /// Opens a trip's details (where its recorded route is shown).
    var onOpenTrip: (String) -> Void = { _ in }
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: String?

    /// Above this many trips the markers drop their mode glyph; above `compactLimit` they shrink to a dot (the selected
    /// one keeps its number). Every trip keeps a marker: it is the only way to select a trip on the map.
    private static let glyphLimit = 8
    private static let compactLimit = 20

    var body: some View {
        Map(position: $position) {
            ForEach(data.connections) { c in
                let dim = selected != nil && selected != c.id
                ForEach(Array(c.spans.enumerated()), id: \.offset) { _, span in
                    let style = SchematicStyle.of(span.kind)
                    let coords = span.coordinates.map(\.cl)
                    let width: CGFloat = selected == c.id ? 5.5 : 4
                    // an ink casing with the same dash pattern keeps light colours legible on the muted map
                    MapPolyline(coordinates: coords)
                        .stroke(Toon.ink.opacity(dim ? 0.15 : 0.85), style: style.stroke(width: width + 3))
                    MapPolyline(coordinates: coords)
                        .stroke(style.color.opacity(dim ? 0.3 : 1), style: style.stroke(width: width))
                }
            }
            ForEach(data.connections) { c in
                Annotation("", coordinate: c.marker.cl, anchor: .center) {
                    marker(c)
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
        .overlay(alignment: .top) { caption.padding(8) } // the bottom edge holds the Maps logo and Legal link
        .onAppear { position = Self.camera(for: data) }
        .onChange(of: data.items.map(\.id)) { _, _ in
            position = Self.camera(for: data)
            if let s = selected, !data.connections.contains(where: { $0.id == s }) { selected = nil }
        }
    }

    private func marker(_ c: SchematicTrips.Connection) -> some View {
        let isSelected = selected == c.id
        let style = SchematicStyle.of(SchematicTrips.kind(of: c.mainMode))
        let compact = data.connections.count > Self.compactLimit && !isSelected
        return Button {
            withAnimation(.snappy) { selected = isSelected ? nil : c.id }
        } label: {
            Group {
                if compact {
                    Circle().fill(style.color).overlay(Circle().strokeBorder(Toon.ink, lineWidth: 1.5))
                        .frame(width: 11, height: 11)
                        .frame(width: 24, height: 24).contentShape(Rectangle()) // a dot to see, a finger-sized target
                } else {
                    numbered(c, style: style, isSelected: isSelected)
                }
            }
            .opacity(selected == nil || isSelected ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Trip %lld: %@", c.order, c.mainMode.localizedLabel))
        .accessibilityValue(endpointsText(c))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func numbered(_ c: SchematicTrips.Connection, style: SchematicStyle, isSelected: Bool) -> some View {
        HStack(spacing: 2) {
            if data.connections.count <= Self.glyphLimit || isSelected {
                Image(systemName: c.mainMode.symbol).accessibilityHidden(true) // the button's label names the mode
                    .font(.system(size: 9, weight: .bold)) // a11y-check:disable fixed-font-size (sized to the map marker)
            }
            Text(c.order.formatted()).font(.system(size: 10, weight: .heavy)).monospacedDigit() // a11y-check:disable fixed-font-size (sized to the map marker)
        }
        .foregroundStyle(Toon.ink)
        .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
        .background(Capsule().fill(isSelected ? Toon.paper : style.color))
        .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: isSelected ? 2.5 : 1.5))
        .scaleEffect(isSelected ? 1.25 : 1)
    }

    @ViewBuilder private var caption: some View {
        if let id = selected, let c = data.connections.first(where: { $0.id == id }),
           let t = data.trips.first(where: { $0.id == id }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Trip %lld: %@", c.order, t.displayModes.map(\.localizedLabel).joined(separator: " + ")))
                        .font(.toon(12, .heavy)).foregroundStyle(Toon.ink).toonLineLimit(2)
                    Text("\(endpointsText(c)) · \(Fmt.time(t.departure))–\(Fmt.time(t.arrival))")
                        .font(.toon(11, .semibold)).foregroundStyle(Toon.muted).toonLineLimit(2).monospacedDigit()
                }
                Spacer(minLength: 0)
                Button("Details") { onOpenTrip(id) }
                    .buttonStyle(ToonButtonStyle(fill: Toon.accent, height: 28, fontSize: 11, shadow: 2))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Toon.paper))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Toon.ink, lineWidth: 2))
        } else if !data.connections.isEmpty {
            Text("Lines join stops; they are not the routes taken")
                .font(.toon(10, .bold)).foregroundStyle(Toon.muted)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Toon.paper.opacity(0.9)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        }
    }

    private func endpointsText(_ c: SchematicTrips.Connection) -> String {
        guard let t = data.trips.first(where: { $0.id == c.id }) else { return "" }
        func name(_ visitID: String?, _ placeID: String?) -> String {
            let p = (visitID.flatMap { data.visitsByID[$0] }?.placeID ?? placeID).flatMap { data.places[$0] }
            return p.flatMap { $0.isNamed ? $0.displayName : nil } ?? p?.address ?? L("Unnamed place")
        }
        return L("%@ → %@", name(t.originVisitID, t.originPlaceID), name(t.destinationVisitID, t.destinationPlaceID))
    }

    /// Fit everything, but never closer than ~1 km across (a lone visit would otherwise zoom to street level).
    static func camera(for data: DayData) -> MapCameraPosition {
        let coords = data.visits.map { v in (v.placeID.flatMap { data.places[$0] }?.coordinate ?? v.coordinate) }
            + data.connections.flatMap(\.path) + data.unmatchedStamps.compactMap(\.coordinate)
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

/// How each kind of schematic trip connection looks (issue #109): one place to tune it. Colours follow the diary's mode
/// colours so a trip looks the same on the map and in the list; the dash pattern tells modes apart at a glance.
struct SchematicStyle {
    let color: Color
    let dash: [CGFloat]

    /// The dash pattern is fixed, not scaled by `width`, so the wider ink casing stays in step with the colour on top.
    func stroke(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: dash.isEmpty || dash[0] < 1 ? .round : .butt, // a dash under 1 pt with round caps is a dot
                     lineJoin: .round, dash: dash)
    }

    static func of(_ kind: SchematicTrips.Kind) -> SchematicStyle {
        switch kind {
        case .walking: return SchematicStyle(color: TravelMode.walk.color, dash: [0.1, 9])      // dotted
        case .cycling: return SchematicStyle(color: TravelMode.bicycle.color, dash: [7, 5])    // short dashes
        case .driving: return SchematicStyle(color: TravelMode.car.color, dash: [])            // solid
        case .bus: return SchematicStyle(color: TravelMode.bus.color, dash: [16, 6])           // long dashes
        case .rail: return SchematicStyle(color: TravelMode.subway.color, dash: [])            // solid
        case .ferry: return SchematicStyle(color: TravelMode.ferry.color, dash: [12, 5, 3, 5]) // dash-dot
        case .flight: return SchematicStyle(color: TravelMode.airplane.color, dash: [20, 8])   // long-dashed arc
        case .other: return SchematicStyle(color: TravelMode.unknown.color, dash: [8, 6])      // neutral dashes
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
        Image(systemName: symbol).accessibilityHidden(true) // the name tag below is what VoiceOver reads
            // the glyph is sized to the map pin, which stays put on the map; the name tag below scales
            .font(.system(size: size * 0.45, weight: .bold)) // a11y-check:disable fixed-font-size
            .foregroundStyle(Toon.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(Toon.ink, lineWidth: 2.5))
            .background(Circle().fill(Toon.ink).offset(x: 1.5, y: 2))
            .overlay(alignment: .top) {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.toon(11, .heavy)).foregroundStyle(Toon.ink)
                        .fixedSize()
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
        HStack(alignment: .top, spacing: 12) { // a11y-check:disable heading-trait-missing (its text is a status line)
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
        let points = model.progress.map { " · " + L("%@ points", $0.report.pointsConsidered.formatted()) } ?? ""
        switch model.phase {
        case .syncingMotion, nil: return L("Syncing motion activity")
        case .engine(.loadingPoints): return L("Loading location points")
        case .engine(.detectingStays): return L("Detecting stays") + points
        case .engine(.resolvingVisits):
            let p = model.progress
            return L("Matching visits") + (p.map { $0.staysTotal > 0 ? " " + L("(%lld of %lld)", $0.staysResolved, $0.staysTotal) : "" } ?? "") + points
        case .engine(.buildingTrips): return L("Building trips") + points
        case .engine(.finalizing): return L("Saving")
        }
    }

    private func detailText(now: Date) -> String {
        var parts: [String] = []
        if let r = model.progress?.report {
            let visits = r.visitsCreated + r.visitsUpdated
            if visits > 0 { parts.append(L("%lld visits so far", visits)) }
            if r.tripsCreated > 0 { parts.append(L("%lld trips", r.tripsCreated)) }
        }
        if let s = model.runStartedAt {
            let e = Int(max(0, now.timeIntervalSince(s)))
            parts.append(L("%@ elapsed", String(format: "%d:%02d", e / 60, e % 60)))
        }
        if model.rerunRequested { parts.append(L("another update queued")) }
        return parts.joined(separator: " · ")
    }
}

/// The end of the timeline when raw data exists past the last stop that no run has turned into a visit or trip yet.
struct PendingActivityRow: View {
    /// grows with the icon inside it
    @ScaledMetric(relativeTo: .subheadline) private var iconTile: CGFloat = 28
    @EnvironmentObject var model: AppModel
    let tail: InferenceEngine.UnresolvedTail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.isProcessing ? "hourglass" : "ellipsis").accessibilityHidden(true)
                .font(.toon(14, .semibold))
                .foregroundStyle(.orange)
                .frame(width: iconTile, height: iconTile)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
            VStack(alignment: .leading, spacing: 2) {
                Text("Not in your diary yet").font(.subheadline.weight(.medium)) // a11y-check:disable heading-trait-missing (a status line)
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
