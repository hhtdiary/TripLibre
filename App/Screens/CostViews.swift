import SwiftUI
import HHTCore

// MARK: - Money formatting

enum CostStyle {
    static let symbol = "creditcard.fill"
    static let color = Toon.mint
}

extension Fmt {
    /// "$2.90", "€14", "¥800": the currency's own symbol and decimals.
    static func money(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).presentation(.narrow))
    }

    /// One cost as shown on a badge: "Free" for a zero.
    static func cost(_ e: Expense) -> String { e.amount == 0 ? "Free" : money(e.amount, e.currency) }

    /// Several costs: summed per currency, largest first ("$5.80 + €3").
    static func costs(_ es: [Expense]) -> String? {
        guard !es.isEmpty else { return nil }
        if es.allSatisfy({ $0.amount == 0 }) { return "Free" }
        var by: [String: Double] = [:]
        for e in es { by[e.currency, default: 0] += e.amount }
        return by.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { money($0.value, $0.key) }.joined(separator: " + ")
    }

    /// Accepts "2.90", "2,90", "$2.90", " 12 ": nil when it isn't a non-negative number.
    static func parseAmount(_ s: String) -> Double? {
        // a minus sign anywhere ("-12.50", "$-3", "−4") makes it negative, not something to strip
        guard !s.contains(where: { $0 == "-" || $0 == "\u{2212}" }) else { return nil }
        var t = s.filter { $0.isNumber || $0 == "." || $0 == "," }
        if !t.contains(".") { t = t.replacingOccurrences(of: ",", with: ".") } else { t = t.replacingOccurrences(of: ",", with: "") }
        guard !t.isEmpty, let v = Double(t), v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// The amount as typed back into the field ("2.9" → "2.90" for cents currencies, "800" for yen).
    static func amountText(_ amount: Double, _ currency: String) -> String {
        let digits = Locale.Currency(currency).minorUnitDigits
        return amount.formatted(.number.precision(.fractionLength(amount.rounded() == amount ? 0 : digits)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}

private extension Locale.Currency {
    /// Decimal places the currency uses (2 for USD, 0 for JPY).
    var minorUnitDigits: Int {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = identifier
        return f.maximumFractionDigits
    }
}

// MARK: - What a cost is for

/// Where a new cost is being added from.
enum CostTarget {
    case trip(Trip)
    case visit(Visit, Place?)
    /// The day's "Add cost": the user picks a trip or visit of `day`, or none.
    case day(Date)
}

/// Which cost sheet is open: a new cost (for a trip, a visit, or the day) or an existing one.
struct CostSheet: Identifiable {
    var target: CostTarget
    var existing: Expense?
    /// The day on screen when it was opened from Today's prompt: a cost for a stay is kept on that day.
    var day: Date?
    var id: String { existing?.id ?? "new" }
}

/// One choice in the "For" picker.
private struct CostLink: Hashable, Identifiable {
    var tripID: String?
    var visitID: String?
    var title: String
    var symbol: String
    var id: String { tripID.map { "t-" + $0 } ?? visitID.map { "v-" + $0 } ?? "day" }
    static let none = CostLink(title: "Nothing specific (just this day)", symbol: "calendar")
}

// MARK: - Entry sheet

/// Add or edit one cost. Opens with the amount field focused; the category is pre-picked from the trip's mode or the
/// place's category, and the last amounts paid for the same mode or place are one tap away.
struct CostEntrySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: CostTarget
    var existing: Expense?
    /// The day on screen, when opened from Today's prompt for a stay (see `CostSheet.day`).
    var day: Date?

    @AppStorage("costCurrency") private var lastCurrency = Expense.defaultCurrency
    @State private var amountText = ""
    /// Category tiles get wider as their labels grow with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var categoryTileWidth: CGFloat = 96
    @State private var currency = Expense.defaultCurrency
    @State private var category: ExpenseCategory = .other
    @State private var categoryTouched = false
    @State private var note = ""
    @State private var time = Date()
    @State private var link = CostLink.none
    @State private var links: [CostLink] = []
    @State private var trips: [String: Trip] = [:]
    @State private var visits: [String: (Visit, Place?)] = [:]
    @State private var suggestions: [Expense] = []
    @State private var confirmDelete = false
    @State private var didSetUp = false
    @FocusState private var amountFocused: Bool

    private var amount: Double? { Fmt.parseAmount(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        currencyMenu
                        TextField("0.00", text: $amountText)
                            .font(.toon(34, .bold)).monospacedDigit()
                            .decimalKeyboard()
                            .focused($amountFocused)
                            .accessibilityLabel("Amount")
                            .accessibilityIdentifier("costAmount")
                    }
                    if !suggestions.isEmpty || isTripLink {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions) { s in
                                    Button(Fmt.cost(s)) {
                                        amountText = Fmt.amountText(s.amount, s.currency)
                                        currency = s.currency
                                        if !categoryTouched { category = s.category }
                                    }
                                    .buttonStyle(ToonButtonStyle(fill: Toon.cream, height: 32, fontSize: 13, shadow: 2))
                                }
                                if isTripLink {
                                    Button("Free / pass") { amountText = "0" }
                                        .buttonStyle(ToonButtonStyle(fill: Toon.cream, height: 32, fontSize: 13, shadow: 2))
                                }
                            }
                            .padding(.vertical, 4).padding(.trailing, 4)
                        }
                    }
                } header: {
                    Text(header)
                        .toonSectionText()
                } footer: {
                    Group {
                        if !amountText.isEmpty && amount == nil { Text("Enter an amount like 2.90.").foregroundStyle(Toon.accentDeep) }
                    }
                    .toonSectionText()
                }

                if links.count > 1 {
                    Section {
                        Picker("For", selection: $link) {
                            ForEach(links) { l in Label(l.title, systemImage: l.symbol).tag(l) }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: categoryTileWidth), spacing: 8)], spacing: 8) {
                        ForEach(ExpenseCategory.allCases) { c in
                            Button {
                                category = c
                                categoryTouched = true
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: c.symbol).font(.title3).accessibilityHidden(true)
                                    Text(c.label).font(.caption2).toonLineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(category == c ? CostStyle.color.opacity(0.35) : Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(category == c ? Toon.ink : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("What for").toonSectionText() }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                    if link == .none {
                        DatePicker("When", selection: $time, in: ...Date())
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Remove this cost", systemImage: "trash") }
                    }
                }
            }
            .groupedList()
            .navigationTitle(existing == nil ? "Add a cost" : "Edit cost")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(amount == nil).accessibilityIdentifier("costSave")
                    .confirmTint()
                }
            }
            .confirmationDialog("Remove this cost?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let e = existing { model.perform { try model.edit.deleteExpense(e.id) } }
                    dismiss()
                }
            }
            .onChange(of: link) { _, _ in refreshSuggestions() }
            .onAppear(perform: setUp)
        }
    }

    private var isTripLink: Bool { link.tripID != nil }
    private var isDayTarget: Bool { if case .day = target { return true } else { return false } }

    private var header: String {
        if let id = link.tripID, let t = trips[id] {
            return "\(t.displayModes.map(\.label).joined(separator: " + ")) · \(Fmt.time(t.departure))–\(Fmt.time(t.arrival))"
        }
        if let id = link.visitID, let (v, p) = visits[id] {
            return "At \(Self.name(p) ?? "an unnamed place") · from \(Fmt.time(v.arrival))"
        }
        return "Spent on \(Fmt.shortDay(time))"
    }

    private var currencyMenu: some View {
        let common = [lastCurrency, Expense.defaultCurrency, "USD", "EUR", "GBP", "CNY", "JPY", "CAD", "AUD", "CHF", "HKD", "MXN"]
        let shown = common.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Menu {
            ForEach(shown, id: \.self) { c in Button(currencyName(c)) { currency = c } }
            Menu("More currencies") {
                ForEach(Locale.commonISOCurrencyCodes.filter { !shown.contains($0) }, id: \.self) { c in
                    Button(currencyName(c)) { currency = c }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currency)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .black))
            }
            .font(.toon(15, .heavy)).foregroundStyle(Toon.ink)
            .padding(.horizontal, 10).frame(minHeight: 40)
            .toonCard(CostStyle.color, radius: 12, shadow: 2)
        }
        .accessibilityLabel("Currency: \(currency)")
    }

    private func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code).map { "\(code) · \($0)" } ?? code
    }

    private func setUp() {
        // onAppear fires again when the "For" picker pops back: setting up twice would undo the pick (issue #75)
        guard !didSetUp else { return }
        didSetUp = true
        let store = model.store
        var day = Date()
        switch target {
        case .trip(let t): trips[t.id] = t; link = Self.link(t); day = t.departure
        case .visit(let v, let p): visits[v.id] = (v, p); link = Self.link(v, p); day = v.arrival
        case .day(let d): day = d
        }
        if let e = existing { day = e.timestamp }
        // a new cost from a trip or visit sheet is for that record; otherwise offer the day's trips and visits
        guard existing != nil || isDayTarget else {
            links = [link]
            finishSetUp(day: day)
            return
        }
        let r = DateRange.day(day)
        for t in (try? store.trips(overlapping: r.start, r.end)) ?? [] { trips[t.id] = t }
        for v in (try? store.visits(overlapping: r.start, r.end)) ?? [] { visits[v.id] = (v, v.placeID.flatMap { try? store.place($0) }) }
        let items = trips.values.map { ($0.departure, Self.link($0)) } + visits.values.map { ($0.0.arrival, Self.link($0.0, $0.1)) }
        links = [.none] + items.sorted { $0.0 > $1.0 }.map(\.1)
        if existing == nil {
            // what you're most likely paying for right now: where you are, else nothing in particular
            let isToday = Calendar.current.isDateInToday(day)
            link = isToday ? (visits.values.first { $0.0.departure == nil }.map { Self.link($0.0, $0.1) } ?? .none) : .none
        }
        finishSetUp(day: day)
    }

    private func finishSetUp(day: Date) {
        if let e = existing {
            amountText = Fmt.amountText(e.amount, e.currency)
            currency = e.currency
            category = e.category
            categoryTouched = true
            note = e.note ?? ""
            time = e.timestamp
            link = links.first { $0.tripID == e.tripID && $0.visitID == e.visitID && (e.tripID != nil || e.visitID != nil) } ?? .none
        } else {
            currency = lastCurrency
            time = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            amountFocused = true
        }
        refreshSuggestions()
    }

    /// Amounts paid before for the same mode or place, newest first, without repeats.
    private func refreshSuggestions() {
        var recent: [Expense] = []
        if let id = link.tripID, let t = trips[id] {
            recent = (try? model.store.recentExpenses(mode: t.mode)) ?? []
            if !categoryTouched { category = ExpenseCategory.suggested(for: t.mode) }
        } else if let id = link.visitID, let (_, p) = visits[id] {
            recent = p.flatMap { try? model.store.recentExpenses(placeID: $0.id) } ?? []
            if !categoryTouched { category = ExpenseCategory.suggested(for: p?.category) }
        }
        var seen = Set<String>()
        suggestions = Array(recent.filter { $0.amount > 0 && seen.insert("\($0.amount)-\($0.currency)").inserted }.prefix(3))
    }

    private func save() {
        guard let amount else { return }
        var e = existing ?? Expense(timestamp: time, amount: amount, currency: currency, category: category)
        e.amount = amount
        e.currency = currency
        e.category = category
        e.note = note
        e.tripID = link.tripID
        e.visitID = link.visitID
        if let id = link.tripID, let t = trips[id] {
            if existing?.tripID != id { e.timestamp = t.departure }
            e.timeZone = t.timeZone
        } else if let id = link.visitID, let (v, _) = visits[id] {
            if existing?.visitID != id {
                if isDayTarget {
                    // added from a day's card: keep it on that day, within the part of the stay that falls on it
                    e.timestamp = Self.costTime(v, on: time, preferring: time)
                } else if let day {
                    // from Today's prompt for that day (issue #75)
                    e.timestamp = Self.costTime(v, on: day)
                } else {
                    // a cost during an ongoing stay is dated now; otherwise when the stay began
                    e.timestamp = v.departure == nil ? max(v.arrival, Date()) : v.arrival
                }
            }
            e.timeZone = v.timeZone
        } else {
            e.timestamp = time
        }
        model.saveCost(e)
        dismiss()
    }

    /// When a cost for stay `v` added while looking at `day` is dated: `preferred` (by default now on today, else the
    /// start of the stay's part of the day), kept within the part of the stay that falls on `day`.
    static func costTime(_ v: Visit, on day: Date, preferring preferred: Date? = nil) -> Date {
        let d = DateRange.day(day)
        let lo = max(v.arrival, d.start), hi = min(v.departure ?? Date(), d.end)
        let want = preferred ?? (Calendar.current.isDateInToday(day) ? Date() : lo)
        return lo <= hi ? min(max(want, lo), hi) : want
    }

    private static func name(_ p: Place?) -> String? { p.flatMap { $0.isNamed ? $0.displayName : nil } }

    private static func link(_ t: Trip) -> CostLink {
        CostLink(tripID: t.id, title: "\(t.displayModes.map(\.label).joined(separator: " + ")) · \(Fmt.time(t.departure))",
                 symbol: t.mode.symbol)
    }

    private static func link(_ v: Visit, _ p: Place?) -> CostLink {
        CostLink(visitID: v.id, title: "\(name(p) ?? "Unnamed place") · \(Fmt.time(v.arrival))",
                 symbol: p?.category?.symbol ?? "mappin")
    }
}

// MARK: - Today

/// Pip asks about one trip or stay that usually costs something and has no cost yet: one tap for the usual amount,
/// "Free" / "Nothing", or more. Today shows one card for each (issue #75).
struct CostPromptCard: View {
    @EnvironmentObject var model: AppModel
    let prompt: CostPrompt
    var onMore: () -> Void
    @State private var suggestions: [Expense] = []
    @State private var saved = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.toon(15, .heavy))
                    Text(subtitle).font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                }
                Spacer(minLength: 0)
                Button { model.skipCostPrompt(prompt.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .black)).foregroundStyle(Toon.muted)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isTrip ? "Don't ask about this trip" : "Don't ask about this visit")
            }
            .foregroundStyle(Toon.ink)
            ToonRowStack(spacing: 6) {
                ForEach(suggestions) { s in
                    Button(Fmt.cost(s)) { quickSave(s.amount, s.currency, s.category) }
                        .buttonStyle(ToonButtonStyle(fill: CostStyle.color, height: 34, fontSize: 13, shadow: 2))
                }
                Button(isTrip ? "Free" : "Nothing") { quickSave(0, model.costCurrency, category) }
                    .buttonStyle(ToonButtonStyle(height: 34, fontSize: 13, shadow: 2))
                    .accessibilityHint(isTrip ? "Records that this trip cost nothing, e.g. with a pass" : "Records that you spent nothing here")
                Button { onMore() } label: { Label(suggestions.isEmpty ? "Enter amount" : "Other", systemImage: "plus") }
                    .buttonStyle(ToonButtonStyle(height: 34, fontSize: 13, shadow: 2))
                    .accessibilityIdentifier("costPromptMore")
            }
        }
        .padding(12)
        .toonCard(Toon.cream, radius: 18, shadow: 0, dashed: true)
        .sensoryFeedback(.success, trigger: saved)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("costPrompt")
        .task(id: prompt.id) {
            let recent: [Expense]
            switch prompt.target {
            case .trip(let t): recent = (try? model.store.recentExpenses(mode: t.mode)) ?? []
            case .visit(_, let p): recent = p.flatMap { try? model.store.recentExpenses(placeID: $0.id) } ?? []
            case .day: recent = []
            }
            var seen = Set<String>()
            suggestions = Array(recent.filter { $0.amount > 0 && seen.insert("\($0.amount)-\($0.currency)").inserted }.prefix(2))
        }
    }

    private var isTrip: Bool { if case .trip = prompt.target { return true } else { return false } }

    @ViewBuilder private var icon: some View {
        switch prompt.target {
        case .trip(let t): ModeIcon(mode: t.mode, size: 34)
        case .visit(_, let p): ToonChip(symbol: p?.category?.symbol ?? "mappin", color: CostStyle.color, size: 34)
        case .day: EmptyView()
        }
    }

    private var title: String {
        switch prompt.target {
        case .trip(let t): return "What did that \(t.mode.label.lowercased()) trip cost?"
        case .visit(_, let p): return "What did you spend at \(p.flatMap { $0.isNamed ? $0.displayName : nil } ?? "this stop")?"
        case .day: return ""
        }
    }

    private var subtitle: String {
        switch prompt.target {
        case .trip(let t): return "\(Fmt.time(t.departure))–\(Fmt.time(t.arrival))" + (prompt.destination.map { " · to \($0)" } ?? "")
        case .visit(let v, _): return v.departure.map { "\(Fmt.time(v.arrival))–\(Fmt.time($0))" } ?? "Since \(Fmt.time(v.arrival))"
        case .day: return ""
        }
    }

    private var category: ExpenseCategory {
        switch prompt.target {
        case .trip(let t): return ExpenseCategory.suggested(for: t.mode)
        case .visit(_, let p): return ExpenseCategory.suggested(for: p?.category)
        case .day: return .other
        }
    }

    private func quickSave(_ amount: Double, _ currency: String, _ category: ExpenseCategory) {
        saved += 1
        switch prompt.target {
        case .trip(let t):
            model.saveCost(Expense(timestamp: t.departure, amount: amount, currency: currency, category: category,
                                   tripID: t.id, timeZone: t.timeZone))
        case .visit(let v, _):
            // on the day being shown, not today: a stay can run across several days (issue #75)
            model.saveCost(Expense(timestamp: CostEntrySheet.costTime(v, on: prompt.day), amount: amount, currency: currency, category: category,
                                   visitID: v.id, timeZone: v.timeZone))
        case .day: break
        }
    }
}

/// One trip or stay Today asks about.
struct CostPrompt: Identifiable {
    var target: CostTarget
    /// The day being shown.
    var day: Date
    /// Where a trip went, if the place has a name.
    var destination: String?
    /// The trip's or visit's ID, also what "don't ask" remembers.
    var id: String
}

/// What the day cost so far, with "+ Cost". Tapping the card opens the spending summary.
struct DaySpendCard: View {
    let costs: [Expense]
    let isToday: Bool
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        ToonRowStack {
            // the totals open the Spending page: one element the size of the whole left part, so VoiceOver and the
            // hit-region audit see a single target rather than each small label (issue #67)
            HStack(spacing: 12) {
                ToonChip(symbol: CostStyle.symbol, color: CostStyle.color, size: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isToday ? "Spent today" : "Spent this day").font(.toon(12)).foregroundStyle(Toon.muted)
                    if let total = Fmt.costs(costs) {
                        Text(total).font(.toon(20, .bold)).monospacedDigit().toonLineLimit(1, minScale: 0.6)
                        Text("\(costs.count) cost\(costs.count == 1 ? "" : "s") · see spending")
                            .font(.toon(11, .bold)).foregroundStyle(Toon.muted)
                    } else {
                        Text("Nothing logged").font(.toon(17, .bold))
                        Text("Tap to see your spending").font(.toon(11, .bold)).foregroundStyle(Toon.muted)
                    }
                }
                .foregroundStyle(Toon.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens your spending")
            .accessibilityAction { onOpen() }
            .accessibilityIdentifier("daySpend")
            Button(action: onAdd) { Label("Cost", systemImage: "plus") }
                .buttonStyle(ToonButtonStyle(fill: Toon.sun, height: 40, fontSize: 14, shadow: 3))
                .accessibilityLabel("Add a cost")
                .accessibilityIdentifier("addCost")
        }
        .padding(12)
        .toonCard(radius: 20, shadow: 3)
    }
}

/// A cost on neither a trip nor a visit, in the day's timeline.
struct CostRow: View {
    let cost: Expense

    var body: some View {
        ToonRowStack {
            ToonChip(symbol: cost.category.symbol, color: CostStyle.color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                ToonRowStack(spacing: 6) {
                    Text(Fmt.cost(cost)).font(.toon(16, .bold)).monospacedDigit()
                    Text(cost.category.label).font(.toon(13, .bold)).foregroundStyle(Toon.muted)
                }
                Text(Fmt.time(cost.timestamp, tz: cost.timeZone)).font(.toon(12, .bold)).monospacedDigit().foregroundStyle(Toon.muted)
                if let n = cost.note { Text(n).font(.toon(12, .semibold)).foregroundStyle(Toon.muted).toonLineLimit(2) }
            }
            .foregroundStyle(Toon.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .toonCard(radius: 18, shadow: 2)
        }
    }
}

/// "$2.90" on a trip or visit row.
struct CostBadge: View {
    let costs: [Expense]
    var body: some View {
        if let text = Fmt.costs(costs) {
            HStack(spacing: 4) {
                Image(systemName: CostStyle.symbol).font(.system(size: 10, weight: .bold))
                Text(text).font(.toon(11, .black)).monospacedDigit()
            }
            .foregroundStyle(Toon.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(CostStyle.color))
            .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cost \(text)")
        }
    }
}

// MARK: - Trip / visit detail

/// The "Cost" section of a trip or visit sheet. The entry sheet is presented by the parent (`sheet`), outside the
/// list: a sheet on a list row is torn down when the row is re-laid out, e.g. as the keyboard hides (issue #75).
struct CostsSection: View {
    let costs: [Expense]
    let target: CostTarget
    @Binding var sheet: CostSheet?

    var body: some View {
        Section {
            ForEach(costs) { e in
                Button { sheet = CostSheet(target: target, existing: e) } label: {
                    HStack {
                        Image(systemName: e.category.symbol).frame(width: 24).foregroundStyle(Toon.muted).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.category.label)
                            if let n = e.note { Text(n).font(.caption).foregroundStyle(Toon.muted).toonLineLimit(1) }
                        }
                        Spacer()
                        Text(Fmt.cost(e)).monospacedDigit().fontWeight(.semibold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { sheet = CostSheet(target: target) } label: { Label(costs.isEmpty ? "Add a cost" : "Add another cost", systemImage: "plus.circle") }
                .accessibilityIdentifier("detailAddCost")
        } header: {
            Text("Cost")
                .toonSectionText()
        } footer: {
            Group {
                if costs.isEmpty {
                    Text(footer)
                } else if costs.count > 1, let total = Fmt.costs(costs) {
                    Text("Total \(total)")
                }
            }
            .toonSectionText()
        }
    }

    private var footer: String {
        if case .trip = target { return "Fares, tickets, a taxi, parking: what getting there cost. Saving a cost keeps this trip as it is when the day is reprocessed." }
        return "Meals, tickets, shopping: what you spent while here. Saving a cost keeps this visit as it is when the day is reprocessed."
    }
}
