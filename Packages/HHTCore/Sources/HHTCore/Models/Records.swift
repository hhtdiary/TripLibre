import Foundation

public func newID() -> String { UUID().uuidString.lowercased() }

/// One observation from the device (never modified after insert).
public struct RawPoint: Equatable, Sendable {
    public var id: Int64?
    public var timestamp: Date
    public var coordinate: Coordinate
    public var horizontalAccuracy: Double?
    public var altitude: Double?
    public var verticalAccuracy: Double?
    public var speed: Double?          // m/s, nil if invalid
    public var speedAccuracy: Double?
    public var course: Double?
    public var source: String          // gps | visit_arrival | visit_departure | significant_change | region_exit | imported
    public var collectorMode: String?  // moving | stationary
    public var timeZone: String?

    public init(id: Int64? = nil, timestamp: Date, coordinate: Coordinate, horizontalAccuracy: Double? = 10,
                altitude: Double? = nil, verticalAccuracy: Double? = nil, speed: Double? = nil,
                speedAccuracy: Double? = nil, course: Double? = nil, source: String = "gps",
                collectorMode: String? = nil, timeZone: String? = TimeZone.current.identifier) {
        self.id = id
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.source = source
        self.collectorMode = collectorMode
        self.timeZone = timeZone
    }
}

/// A CoreMotion activity classification sample (start of an activity episode).
public struct MotionSample: Equatable, Sendable {
    public enum Activity: String, Sendable { case stationary, walking, running, cycling, automotive, unknown }
    public var timestamp: Date
    public var activity: Activity
    public var confidence: Int   // 0 low, 1 medium, 2 high
    public init(timestamp: Date, activity: Activity, confidence: Int) {
        self.timestamp = timestamp
        self.activity = activity
        self.confidence = confidence
    }
}

public struct Place: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String?
    public var coordinate: Coordinate
    public var radius: Double
    public var address: String?
    public var city: String?
    public var region: String?
    public var country: String?
    public var category: PlaceCategory?
    public var code: String?           // IATA / station code etc.
    public var favorite: Bool
    public var notes: String?
    public var source: RecordSource
    public var mergedInto: String?
    public var deleted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), name: String? = nil, coordinate: Coordinate, radius: Double = 100,
                address: String? = nil, city: String? = nil, region: String? = nil, country: String? = nil,
                category: PlaceCategory? = nil, code: String? = nil, favorite: Bool = false, notes: String? = nil,
                source: RecordSource = .inferred, mergedInto: String? = nil, deleted: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.coordinate = coordinate; self.radius = radius
        self.address = address; self.city = city; self.region = region; self.country = country
        self.category = category; self.code = code; self.favorite = favorite; self.notes = notes
        self.source = source; self.mergedInto = mergedInto; self.deleted = deleted; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let address, !address.isEmpty { return address }
        return String(format: "Place %.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
    public var isNamed: Bool { !(name ?? "").isEmpty }
}

public struct Visit: Identifiable, Equatable, Sendable {
    public var id: String
    public var placeID: String?
    public var arrival: Date
    public var departure: Date?        // nil = ongoing
    public var coordinate: Coordinate  // observed centroid
    public var purpose: TripPurpose?
    public var autoConfidence: Double?
    public var source: RecordSource
    public var userStatus: UserStatus
    public var deleted: Bool
    public var timeZone: String?
    public var pointCount: Int?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), placeID: String? = nil, arrival: Date, departure: Date?, coordinate: Coordinate,
                purpose: TripPurpose? = nil, autoConfidence: Double? = nil, source: RecordSource = .inferred,
                userStatus: UserStatus = .auto, deleted: Bool = false, timeZone: String? = TimeZone.current.identifier,
                pointCount: Int? = nil, notes: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.placeID = placeID; self.arrival = arrival; self.departure = departure
        self.coordinate = coordinate; self.purpose = purpose; self.autoConfidence = autoConfidence
        self.source = source; self.userStatus = userStatus; self.deleted = deleted; self.timeZone = timeZone
        self.pointCount = pointCount; self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public func duration(now: Date = Date()) -> TimeInterval { (departure ?? now).timeIntervalSince(arrival) }
}

public struct TripSegment: Identifiable, Equatable, Sendable {
    public var id: String
    public var tripID: String
    public var sequence: Int
    public var start: Date
    public var end: Date
    public var modeAuto: TravelMode?
    public var modeConfidence: Double?
    public var modeUser: TravelMode?
    public var distance: Double
    public var routePolyline: String?

    public init(id: String = newID(), tripID: String, sequence: Int, start: Date, end: Date,
                modeAuto: TravelMode?, modeConfidence: Double?, modeUser: TravelMode? = nil,
                distance: Double, routePolyline: String? = nil) {
        self.id = id; self.tripID = tripID; self.sequence = sequence; self.start = start; self.end = end
        self.modeAuto = modeAuto; self.modeConfidence = modeConfidence; self.modeUser = modeUser
        self.distance = distance; self.routePolyline = routePolyline
    }

    public var mode: TravelMode { modeUser ?? modeAuto ?? .unknown }
    /// True when the user chose or confirmed this segment's mode (it was added by hand, or its mode or bounds edited).
    public var isUserSet: Bool { modeUser != nil }
}

public struct Trip:Identifiable, Equatable, Sendable {
    public var id: String
    public var originVisitID: String?
    public var destinationVisitID: String?
    /// Only for trips without visits (manual / imported history); otherwise the visits' places apply.
    public var originPlaceID: String?
    public var destinationPlaceID: String?
    public var departure: Date
    public var arrival: Date
    public var distance: Double
    public var modeAuto: TravelMode?
    public var modeConfidence: Double?
    public var modeUser: TravelMode?
    public var purpose: TripPurpose?      // explicit override; otherwise destination visit purpose
    public var routePolyline: String?
    public var hasGap: Bool
    public var autoConfidence: Double?
    public var source: RecordSource
    public var userStatus: UserStatus
    public var deleted: Bool
    public var timeZone: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var segments: [TripSegment]

    public init(id: String = newID(), originVisitID: String?, destinationVisitID: String?,
                originPlaceID: String? = nil, destinationPlaceID: String? = nil, departure: Date, arrival: Date,
                distance: Double, modeAuto: TravelMode?, modeConfidence: Double?, modeUser: TravelMode? = nil,
                purpose: TripPurpose? = nil, routePolyline: String? = nil, hasGap: Bool = false,
                autoConfidence: Double? = nil, source: RecordSource = .inferred, userStatus: UserStatus = .auto,
                deleted: Bool = false, timeZone: String? = TimeZone.current.identifier, notes: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(), segments: [TripSegment] = []) {
        self.id = id; self.originVisitID = originVisitID; self.destinationVisitID = destinationVisitID
        self.originPlaceID = originPlaceID; self.destinationPlaceID = destinationPlaceID
        self.departure = departure; self.arrival = arrival; self.distance = distance
        self.modeAuto = modeAuto; self.modeConfidence = modeConfidence; self.modeUser = modeUser
        self.purpose = purpose; self.routePolyline = routePolyline; self.hasGap = hasGap
        self.autoConfidence = autoConfidence; self.source = source; self.userStatus = userStatus
        self.deleted = deleted; self.timeZone = timeZone; self.notes = notes
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.segments = segments
    }

    public var mode: TravelMode { modeUser ?? modeAuto ?? .unknown }
    public var duration: TimeInterval { arrival.timeIntervalSince(departure) }
    /// True when the automatic mode is uncertain and the user has not reviewed it.
    public var needsReview: Bool {
        userStatus == .auto && (modeAuto == nil || modeAuto == .unknown || (modeConfidence ?? 0) < 0.5)
    }
    public var route: [Coordinate] { routePolyline.map(Polyline.decode) ?? [] }
    /// Modes to show for the trip, e.g. [subway, walk] for "Subway / metro + Walk": the segment sequence
    /// (consecutive repeats collapsed) when it is multimodal, else the single trip mode. A whole-trip override
    /// that none of the segments carries (older edits) wins over the segments.
    public var displayModes: [TravelMode] {
        var uniq: [TravelMode] = []
        for m in segments.map(\.mode) where uniq.last != m { uniq.append(m) }
        if uniq.count > 1, modeUser.map(uniq.contains) ?? true { return uniq }
        return [mode]
    }
}

public struct Flight: Identifiable, Equatable, Sendable {
    public var id: String
    public var tripID: String?
    public var journeyID: String?
    public var date: String                 // local date YYYY-MM-DD
    public var originCode: String?
    public var destinationCode: String?
    public var origin: Coordinate?
    public var destination: Coordinate?
    public var departure: Date?
    public var arrival: Date?
    public var airline: String?
    public var flightNumber: String?
    public var aircraftType: String?
    public var seat: String?
    public var cabin: String?
    public var distance: Double?
    public var bookingReference: String?
    public var notes: String?
    public var source: RecordSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), tripID: String? = nil, journeyID: String? = nil, date: String,
                originCode: String? = nil, destinationCode: String? = nil, origin: Coordinate? = nil,
                destination: Coordinate? = nil, departure: Date? = nil, arrival: Date? = nil, airline: String? = nil,
                flightNumber: String? = nil, aircraftType: String? = nil, seat: String? = nil, cabin: String? = nil,
                distance: Double? = nil, bookingReference: String? = nil, notes: String? = nil,
                source: RecordSource = .manual, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.tripID = tripID; self.journeyID = journeyID; self.date = date
        self.originCode = originCode; self.destinationCode = destinationCode; self.origin = origin
        self.destination = destination; self.departure = departure; self.arrival = arrival; self.airline = airline
        self.flightNumber = flightNumber; self.aircraftType = aircraftType; self.seat = seat; self.cabin = cabin
        self.distance = distance; self.bookingReference = bookingReference; self.notes = notes; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// Great-circle distance if both endpoints known, else stored distance.
    public var effectiveDistance: Double? {
        if let o = origin, let d = destination { return Geo.distance(o, d) }
        return distance
    }
    public var routeLabel: String { "\(originCode ?? "???") → \(destinationCode ?? "???")" }
}

/// A one-tap self-report: "something worth recording happened around here, around now" (issue #32).
///
/// The location is deliberately coarse and never treated as the stop's true position: inference uses it only to
/// find the visit the stamp belongs to, or the surrounding GPS fixes that place a short stop it would otherwise miss.
public struct Stamp: Identifiable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    /// Rounded to `Stamp.coordinateDecimals` decimals; nil when there was no usable fix at tap time.
    public var coordinate: Coordinate?
    /// Radius (m) around `coordinate` the stop is believed to lie within (fix accuracy, rounding and fix age).
    public var uncertainty: Double?
    /// Accuracy and age of the fix the coordinate came from, for the record.
    public var fixAccuracy: Double?
    public var fixAge: TimeInterval?
    /// The visit inference attached the stamp to; nil = not (yet) matched to any visit.
    public var visitID: String?
    public var note: String?
    public var timeZone: String?
    public var deleted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), timestamp: Date, coordinate: Coordinate?, uncertainty: Double?,
                fixAccuracy: Double? = nil, fixAge: TimeInterval? = nil, visitID: String? = nil, note: String? = nil,
                timeZone: String? = TimeZone.current.identifier, deleted: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.timestamp = timestamp; self.coordinate = coordinate; self.uncertainty = uncertainty
        self.fixAccuracy = fixAccuracy; self.fixAge = fixAge; self.visitID = visitID; self.note = note
        self.timeZone = timeZone; self.deleted = deleted; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// 3 decimals ≈ 110 m north–south: a block, not a doorway.
    public static let coordinateDecimals = 3
    /// Fixes older than this are not used for a stamp's location (the stamp is still saved, without one).
    public static let maxFixAge: TimeInterval = 10 * 60
    /// Assumed walking speed (m/s) for how far the user may have moved since the fix.
    static let driftSpeed = 1.4

    /// A stamp at `time` with only a coarse location derived from the latest fix, if it is recent enough.
    /// Works with poor or reduced-accuracy fixes (the uncertainty just grows) and with none at all.
    public static func make(at time: Date = Date(), fix: Coordinate?, fixAccuracy: Double?, fixTime: Date?,
                            timeZone: String? = TimeZone.current.identifier) -> Stamp {
        let age = fixTime.map { max(0, time.timeIntervalSince($0)) }
        guard let c = fix, let age, age <= maxFixAge, (fixAccuracy ?? 0) >= 0 else {
            return Stamp(timestamp: time, coordinate: nil, uncertainty: nil, fixAccuracy: fixAccuracy, fixAge: age,
                         timeZone: timeZone)
        }
        let coarse = coarsen(c)
        // the true position is within the fix accuracy of the fix, which is within a rounding cell of `coarse`
        let uncertainty = (fixAccuracy ?? 0) + roundingRadius(at: c.latitude) + driftSpeed * age
        return Stamp(timestamp: time, coordinate: coarse, uncertainty: uncertainty.rounded(), fixAccuracy: fixAccuracy,
                     fixAge: age.rounded(), timeZone: timeZone)
    }

    public static func coarsen(_ c: Coordinate) -> Coordinate {
        let f = pow(10, Double(coordinateDecimals))
        return Coordinate((c.latitude * f).rounded() / f, (c.longitude * f).rounded() / f)
    }

    /// Half the diagonal of a rounding cell: the farthest a true position can be from its rounded coordinate.
    static func roundingRadius(at latitude: Double) -> Double {
        let half = 0.5 / pow(10, Double(coordinateDecimals))
        let dy = half * 111_320, dx = half * 111_320 * cos(latitude * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A named period of life (semester, job, city of residence) used to compare behavior.
public struct LifePhase: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: String?          // semester | job | residence | vacation | research_trip | other
    public var startDate: String      // YYYY-MM-DD (inclusive, local)
    public var endDate: String?       // YYYY-MM-DD (inclusive), nil = ongoing
    public var notes: String?

    public init(id: String = newID(), name: String, kind: String? = nil, startDate: String, endDate: String? = nil, notes: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.startDate = startDate; self.endDate = endDate; self.notes = notes
    }
}

/// One row in the audit log.
public struct AuditEntry: Equatable, Sendable {
    public var timestamp: Date
    public var entityType: String
    public var entityID: String
    public var action: String
    public var field: String?
    public var oldValue: String?
    public var newValue: String?
}
