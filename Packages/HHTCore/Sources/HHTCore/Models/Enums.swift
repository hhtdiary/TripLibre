import Foundation

/// Travel modes. Raw values are the canonical codes written to the database and exports.
public enum TravelMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case walk, run, bicycle, ebike, scooter
    case car                // automobile, driver/passenger not known (typical auto-classification)
    case carDriver = "car_driver"
    case carPassenger = "car_passenger"
    case taxi               // taxi / ridehail
    case bus                // local bus
    case subway             // subway / metro
    case lightRail = "light_rail"   // light rail / streetcar / trolley
    case commuterRail = "commuter_rail"
    case intercityRail = "intercity_rail"
    case coach              // long-distance bus
    case shuttle            // campus / employer shuttle
    case ferry
    case airplane
    case other
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .bicycle: return "Bike"
        case .ebike: return "E-bike"
        case .scooter: return "Scooter"
        case .car: return "Car"
        case .carDriver: return "Car (driver)"
        case .carPassenger: return "Car (passenger)"
        case .taxi: return "Taxi / ridehail"
        case .bus: return "Bus"
        case .subway: return "Subway / metro"
        case .lightRail: return "Light rail / trolley"
        case .commuterRail: return "Commuter rail"
        case .intercityRail: return "Intercity rail"
        case .coach: return "Coach bus"
        case .shuttle: return "Shuttle"
        case .ferry: return "Ferry"
        case .airplane: return "Airplane"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }

    /// SF Symbol name used by the app.
    public var symbol: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .bicycle, .ebike: return "bicycle"
        case .scooter: return "scooter"
        case .car, .carDriver, .carPassenger: return "car.fill"
        case .taxi: return "car.side.fill"
        case .bus, .coach, .shuttle: return "bus.fill"
        case .subway: return "tram.fill.tunnel"
        case .lightRail: return "tram.fill"
        case .commuterRail, .intercityRail: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .airplane: return "airplane"
        case .other: return "ellipsis.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    public var group: ModeGroup {
        switch self {
        case .walk, .run, .bicycle, .ebike, .scooter: return .active
        case .car, .carDriver, .carPassenger, .taxi: return .car
        case .bus, .subway, .lightRail, .commuterRail, .ferry, .shuttle: return .transit
        case .intercityRail, .coach, .airplane: return .longDistance
        case .other, .unknown: return .other
        }
    }
}

public enum ModeGroup: String, CaseIterable, Codable, Sendable {
    case active, car, transit, longDistance = "long_distance", other
    public var label: String {
        switch self {
        case .active: return "Active"
        case .car: return "Car"
        case .transit: return "Transit"
        case .longDistance: return "Long-distance"
        case .other: return "Other / unknown"
        }
    }
}

/// Activity purpose at the destination (HHTS-style).
public enum TripPurpose: String, CaseIterable, Codable, Identifiable, Sendable {
    case home, work, school, meal, shopping, recreation, social
    case personalBusiness = "personal_business"
    case medical
    case travel          // travel / airport / station
    case transfer        // change of mode, not an activity
    case escort          // pick up / drop off someone
    case other

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .home: return "Home"
        case .work: return "Work"
        case .school: return "School"
        case .meal: return "Meal"
        case .shopping: return "Shopping"
        case .recreation: return "Recreation"
        case .social: return "Social"
        case .personalBusiness: return "Personal business"
        case .medical: return "Medical"
        case .travel: return "Travel / airport"
        case .transfer: return "Transfer"
        case .escort: return "Pick-up / drop-off"
        case .other: return "Other"
        }
    }
}

/// Personal place category. Raw values are the canonical codes written to the database and exports;
/// never rename a shipped one (old databases and exports keep it), only append new cases.
public enum PlaceCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case workSchool = "work_school"
    case restaurant, cafe, grocery, shopping, recreation, entertainment
    case airport
    case railStation = "rail_station"
    case transitStation = "transit_station"
    case hotel
    case friendFamily = "friend_family"
    case medical
    case other
    // added for issue #56
    case stadium                                // stadium / arena / sports venue
    case eventVenue = "event_venue"             // theater / concert hall / event venue
    case museum                                 // museum / art gallery
    case library
    case convenienceStore = "convenience_store"
    case gasStation = "gas_station"
    case bar
    case gym
    case pharmacy
    case bank
    case civic                                  // government / civic facility
    case religious                              // place of worship
    case parking

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .home: return "Home"
        case .workSchool: return "Work / School"
        case .restaurant: return "Restaurant"
        case .cafe: return "Cafe"
        case .grocery: return "Grocery / Supermarket"
        case .shopping: return "Shopping / Mall"
        case .recreation: return "Park / Recreation"
        case .entertainment: return "Entertainment"
        case .airport: return "Airport"
        case .railStation: return "Rail station"
        case .transitStation: return "Bus / transit stop"
        case .hotel: return "Hotel / Lodging"
        case .friendFamily: return "Friend / Family"
        case .medical: return "Hospital / Clinic"
        case .other: return "Other"
        case .stadium: return "Stadium / Arena"
        case .eventVenue: return "Theater / Event venue"
        case .museum: return "Museum / Gallery"
        case .library: return "Library"
        case .convenienceStore: return "Convenience store"
        case .gasStation: return "Gas station"
        case .bar: return "Bar / Pub"
        case .gym: return "Gym / Fitness"
        case .pharmacy: return "Pharmacy"
        case .bank: return "Bank"
        case .civic: return "Government / Civic"
        case .religious: return "Place of worship"
        case .parking: return "Parking"
        }
    }
    public var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .workSchool: return "building.columns.fill"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .grocery: return "cart.fill"
        case .shopping: return "bag.fill"
        case .recreation: return "leaf.fill"
        case .entertainment: return "popcorn.fill"
        case .airport: return "airplane.departure"
        case .railStation: return "train.side.front.car"
        case .transitStation: return "tram.fill"
        case .hotel: return "bed.double.fill"
        case .friendFamily: return "person.2.fill"
        case .medical: return "cross.case.fill"
        case .other: return "mappin"
        case .stadium: return "sportscourt.fill"
        case .eventVenue: return "theatermasks.fill"
        case .museum: return "paintpalette.fill"
        case .library: return "books.vertical.fill"
        case .convenienceStore: return "basket.fill"
        case .gasStation: return "fuelpump.fill"
        case .bar: return "wineglass.fill"
        case .gym: return "dumbbell.fill"
        case .pharmacy: return "pills.fill"
        case .bank: return "banknote.fill"
        case .civic: return "building.2.fill"
        case .religious: return "hands.and.sparkles.fill"
        case .parking: return "parkingsign.circle.fill"
        }
    }
    /// Section the category is listed under in the picker.
    public var group: PlaceCategoryGroup {
        switch self {
        case .home, .friendFamily, .workSchool, .hotel: return .personal
        case .restaurant, .cafe, .bar: return .foodDrink
        case .grocery, .convenienceStore, .shopping, .gasStation: return .shopping
        case .recreation, .gym, .stadium, .eventVenue, .museum, .library, .entertainment: return .leisure
        case .medical, .pharmacy, .bank, .civic, .religious: return .services
        case .airport, .railStation, .transitStation, .parking: return .transport
        case .other: return .other
        }
    }
    /// Extra words the picker's search matches besides the label.
    public var keywords: [String] {
        switch self {
        case .home: return ["house", "apartment"]
        case .workSchool: return ["office", "workplace", "university", "college", "campus", "class"]
        case .restaurant: return ["food", "dinner", "lunch"]
        case .cafe: return ["coffee", "café", "bakery"]
        case .grocery: return ["market", "food"]
        case .shopping: return ["store", "retail", "shop"]
        case .recreation: return ["outdoors", "playground", "beach", "trail"]
        case .entertainment: return ["cinema", "movie", "arcade", "bowling"]
        case .airport: return ["flight", "terminal"]
        case .railStation: return ["train", "amtrak"]
        case .transitStation: return ["bus", "subway", "metro", "terminal"]
        case .hotel: return ["motel", "hostel", "airbnb"]
        case .friendFamily: return ["friend", "family", "relative"]
        case .medical: return ["doctor", "dentist", "health"]
        case .other: return []
        case .stadium: return ["arena", "sports", "ballpark", "field", "game"]
        case .eventVenue: return ["concert", "music", "hall", "show", "venue", "opera"]
        case .museum: return ["art", "exhibit"]
        case .library: return ["books", "study"]
        case .convenienceStore: return ["corner", "deli", "bodega", "wawa"]
        case .gasStation: return ["fuel", "petrol", "charging"]
        case .bar: return ["pub", "brewery", "drinks", "nightlife"]
        case .gym: return ["fitness", "workout", "yoga", "pool"]
        case .pharmacy: return ["drugstore", "chemist"]
        case .bank: return ["atm", "finance"]
        case .civic: return ["government", "city hall", "post office", "dmv", "court"]
        case .religious: return ["church", "mosque", "temple", "synagogue", "worship"]
        case .parking: return ["garage", "lot", "park and ride"]
        }
    }
    /// True if `query` matches the label or a keyword (case- and diacritic-insensitive).
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return ([label, group.label] + keywords).contains { $0.range(of: q, options: opts) != nil }
    }
    /// Default activity purpose implied by a place category.
    /// Keep in sync with the CASE in the latest `v_trips` migration (checked by a test).
    public var defaultPurpose: TripPurpose? {
        switch self {
        case .home: return .home
        case .workSchool: return .work
        case .restaurant, .cafe: return .meal
        case .grocery, .shopping, .convenienceStore, .gasStation: return .shopping
        case .recreation, .entertainment, .stadium, .eventVenue, .museum, .library, .gym: return .recreation
        case .airport, .railStation, .hotel: return .travel
        case .transitStation, .parking: return .transfer
        case .friendFamily, .bar, .religious: return .social
        case .medical, .pharmacy: return .medical
        case .bank, .civic: return .personalBusiness
        case .other: return nil
        }
    }
}

/// Picker sections for place categories, in display order.
public enum PlaceCategoryGroup: String, CaseIterable, Identifiable, Sendable {
    case personal, foodDrink, shopping, leisure, services, transport, other

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .personal: return "Home & work"
        case .foodDrink: return "Food & drink"
        case .shopping: return "Shopping & errands"
        case .leisure: return "Leisure & culture"
        case .services: return "Health & services"
        case .transport: return "Travel & transport"
        case .other: return "Other"
        }
    }
    public var categories: [PlaceCategory] { PlaceCategory.allCases.filter { $0.group == self } }
}

/// Provenance of a derived or entered record.
public enum RecordSource: String, Codable, Sendable {
    case inferred, manual
    case importedCSV = "imported_csv"
    case importedGPX = "imported_gpx"
}

/// Edit state of a derived record. Anything other than `.auto` is protected from reprocessing.
public enum UserStatus: String, Codable, Sendable {
    case auto        // produced by inference, untouched
    case confirmed   // user reviewed and accepted as-is
    case edited      // user changed at least one field
    case manual      // user created it
    public var isLocked: Bool { self != .auto }
}

/// What money was spent on (issue #17). Raw values are the canonical codes written to the database and exports;
/// never rename a shipped one, only append new cases.
public enum ExpenseCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case fare            // transit fare, train / bus / ferry ticket, bike share
    case taxi            // taxi / ride-hail
    case fuel            // fuel or charging
    case parking         // parking, tolls
    case flight
    case lodging
    case food            // meals, coffee, snacks
    case admission       // tickets, entry, activities
    case shopping
    case other

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fare: return "Fare / ticket"
        case .taxi: return "Taxi / ride"
        case .fuel: return "Fuel / charging"
        case .parking: return "Parking / tolls"
        case .flight: return "Flight"
        case .lodging: return "Lodging"
        case .food: return "Food & drink"
        case .admission: return "Admission"
        case .shopping: return "Shopping"
        case .other: return "Other"
        }
    }

    /// SF Symbol name used by the app.
    public var symbol: String {
        switch self {
        case .fare: return "ticket.fill"
        case .taxi: return "car.side.fill"
        case .fuel: return "fuelpump.fill"
        case .parking: return "parkingsign"
        case .flight: return "airplane"
        case .lodging: return "bed.double.fill"
        case .food: return "fork.knife"
        case .admission: return "theatermasks.fill"
        case .shopping: return "bag.fill"
        case .other: return "ellipsis.circle"
        }
    }

    /// The cost of getting somewhere, as opposed to spending once there.
    public var isTravel: Bool {
        switch self {
        case .fare, .taxi, .fuel, .parking, .flight: return true
        case .lodging, .food, .admission, .shopping, .other: return false
        }
    }

    /// Best first guess for a cost on a trip by `mode`.
    public static func suggested(for mode: TravelMode) -> ExpenseCategory {
        switch mode {
        case .taxi: return .taxi
        case .airplane: return .flight
        case .car, .carDriver, .carPassenger: return .fuel
        case .walk, .run, .other, .unknown: return .other
        default: return .fare
        }
    }

    /// Best first guess for a cost during a stay at a place of `category`.
    public static func suggested(for category: PlaceCategory?) -> ExpenseCategory {
        switch category {
        case .restaurant, .cafe, .bar, .grocery, .convenienceStore: return .food
        case .shopping, .pharmacy: return .shopping
        case .hotel: return .lodging
        case .museum, .stadium, .eventVenue, .entertainment, .recreation, .gym: return .admission
        case .parking: return .parking
        case .gasStation: return .fuel
        default: return .other
        }
    }
}

extension TravelMode {
    /// Modes that usually cost something per trip, so the app asks about them (issue #17).
    /// Cars are left out: fuel and parking rarely map to one trip.
    public var usuallyPaid: Bool {
        switch self {
        case .taxi, .bus, .subway, .lightRail, .commuterRail, .intercityRail, .coach, .ferry, .airplane: return true
        default: return false
        }
    }
}

extension PlaceCategory {
    /// Places where a stay usually costs something (a meal, a ticket, a room), so the app asks about each visit
    /// there (issue #75). Home, work and other everyday places are left out.
    public var usuallyPaid: Bool { ExpenseCategory.suggested(for: self) != .other }
}
