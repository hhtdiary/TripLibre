import Foundation

/// What the costs in a period add up to (issue #17).
///
/// Amounts in different currencies are never converted or added: everything is computed in the main currency (the one
/// most costs use) and the rest are listed as separate totals. A cost counts as travel when it is on a trip, as spent at a
/// destination when it is on a visit, and by its category when it is on neither.
public struct SpendingSummary: Equatable, Sendable {
    public struct CategoryRow: Identifiable, Equatable, Sendable {
        public var category: ExpenseCategory
        public var total: Double
        public var count: Int
        public var id: String { category.rawValue }
    }

    public struct ModeRow: Identifiable, Equatable, Sendable {
        public var mode: TravelMode
        public var total: Double
        /// Trips by this mode with a cost entered (free ones included).
        public var trips: Int
        public var distance: Double
        public var id: String { mode.rawValue }
        public var perTrip: Double { trips > 0 ? total / Double(trips) : 0 }
        /// Per kilometre over the trips with a cost entered; nil when they have no distance.
        public var perKm: Double? { distance >= 100 ? total / (distance / 1000) : nil }
    }

    public struct PlaceRow: Identifiable, Equatable, Sendable {
        public var placeID: String
        public var name: String
        public var category: PlaceCategory?
        public var total: Double
        public var count: Int
        public var id: String { placeID }
    }

    public var range: DateRange
    public var currency: String
    public var total: Double = 0
    public var travel: Double = 0
    public var atDestinations: Double = 0
    /// Costs in the main currency.
    public var count = 0
    /// Local days with at least one cost in the main currency.
    public var days = 0
    public var byCategory: [CategoryRow] = []
    public var byMode: [ModeRow] = []
    public var byPlace: [PlaceRow] = []
    /// Main-currency total per local day ("YYYY-MM-DD").
    public var byDay: [String: Double] = [:]
    /// Totals in every other currency, unconverted.
    public var otherCurrencies: [String: Double] = [:]

    public var perDay: Double { days > 0 ? total / Double(days) : 0 }
    /// At least one cost in the main currency.
    public var hasMainCurrency: Bool { !byDay.isEmpty }
    public var isEmpty: Bool { !hasMainCurrency && otherCurrencies.isEmpty }
}

extension Analytics {
    public static func spending(store: TravelStore, range: DateRange, defaultCurrency: String = Expense.defaultCurrency) throws -> SpendingSummary {
        let expenses = try store.expenses(from: range.start, to: range.end)
        var trips: [String: Trip] = [:], visits: [String: Visit] = [:]
        for id in Set(expenses.compactMap(\.tripID)) { if let t = try store.trip(id), !t.deleted { trips[id] = t } }
        for id in Set(expenses.compactMap(\.visitID)) { if let v = try store.visit(id), !v.deleted { visits[id] = v } }
        let places = Dictionary(uniqueKeysWithValues: try store.places().map { ($0.id, $0) })
        return spending(expenses: expenses, trips: trips, visits: visits, places: places, range: range,
                        defaultCurrency: defaultCurrency)
    }

    /// Pure computation (unit-testable). Costs linked to a trip or visit missing from the maps count as unlinked.
    public static func spending(expenses all: [Expense], trips: [String: Trip], visits: [String: Visit],
                                places: [String: Place], range: DateRange,
                                defaultCurrency: String = Expense.defaultCurrency) -> SpendingSummary {
        let inRange = all.filter { !$0.deleted && range.contains($0.timestamp) }
        var counts: [String: Int] = [:]
        for e in inRange { counts[e.currency, default: 0] += 1 }
        // most costs wins; ties go to the default currency, then alphabetically, so the choice is stable
        let main = counts.max { a, b in
            a.value != b.value ? a.value < b.value
                : (a.key == defaultCurrency) != (b.key == defaultCurrency) ? b.key == defaultCurrency : a.key > b.key
        }?.key ?? defaultCurrency

        var s = SpendingSummary(range: range, currency: main)
        var cats: [ExpenseCategory: (Double, Int)] = [:]
        var modes: [TravelMode: (total: Double, trips: Set<String>)] = [:]
        var placeRows: [String: (Double, Int)] = [:]
        for e in inRange {
            guard e.currency == main else {
                s.otherCurrencies[e.currency, default: 0] += e.amount
                continue
            }
            s.total += e.amount
            s.count += 1
            s.byDay[dayKey(e.timestamp, tz: e.timeZone), default: 0] += e.amount
            cats[e.category, default: (0, 0)].0 += e.amount
            cats[e.category, default: (0, 0)].1 += 1
            let trip = e.tripID.flatMap { trips[$0] }
            let visit = e.visitID.flatMap { visits[$0] }
            if let trip {
                s.travel += e.amount
                modes[trip.mode, default: (0, [])].total += e.amount
                modes[trip.mode, default: (0, [])].trips.insert(trip.id)
            } else if visit != nil || !e.category.isTravel {
                s.atDestinations += e.amount
            } else {
                s.travel += e.amount
            }
            if let pid = visit?.placeID, places[pid] != nil {
                placeRows[pid, default: (0, 0)].0 += e.amount
                placeRows[pid, default: (0, 0)].1 += 1
            }
        }
        s.days = s.byDay.count
        s.byCategory = cats.map { SpendingSummary.CategoryRow(category: $0.key, total: $0.value.0, count: $0.value.1) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.category.rawValue < $1.category.rawValue }
        s.byMode = modes.map { m, v in
            SpendingSummary.ModeRow(mode: m, total: v.total, trips: v.trips.count,
                                    distance: v.trips.compactMap { trips[$0]?.distance }.reduce(0, +))
        }
        .sorted { $0.total != $1.total ? $0.total > $1.total : $0.mode.rawValue < $1.mode.rawValue }
        s.byPlace = placeRows.compactMap { pid, v in
            places[pid].map { SpendingSummary.PlaceRow(placeID: pid, name: $0.displayName, category: $0.category, total: v.0, count: v.1) }
        }
        .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        return s
    }
}
