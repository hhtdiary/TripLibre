import Foundation
import Testing
@testable import HHTCore

/// Place-category taxonomy (issue #56): backward compatibility, picker grouping/search, storage, views, exports.
@Suite("Place categories")
struct PlaceCategoryTests {

    /// Codes that shipped before #56. They live in old databases and exports and must keep decoding.
    static let legacyCodes = ["home", "work_school", "restaurant", "cafe", "grocery", "shopping", "recreation",
                              "entertainment", "airport", "rail_station", "transit_station", "hotel", "friend_family",
                              "medical", "other"]

    @Test func legacyCodesStillDecode() {
        for code in Self.legacyCodes { #expect(PlaceCategory(rawValue: code)?.rawValue == code) }
        #expect(Set(PlaceCategory.allCases.map(\.rawValue)).count == PlaceCategory.allCases.count)
    }

    @Test func priorityCategoriesExistAndAreDistinct() {
        let added: [PlaceCategory] = [.stadium, .eventVenue, .museum, .library, .convenienceStore, .gasStation]
        #expect(Set(added.map(\.label)).count == added.count)
        #expect(PlaceCategory.stadium.rawValue == "stadium")
        #expect(PlaceCategory.eventVenue.rawValue == "event_venue")
        #expect(PlaceCategory.convenienceStore.rawValue == "convenience_store")
        #expect(PlaceCategory.gasStation.rawValue == "gas_station")
    }

    @Test func groupsPartitionAllCategories() {
        let grouped = PlaceCategoryGroup.allCases.flatMap(\.categories)
        #expect(grouped.count == PlaceCategory.allCases.count)
        #expect(Set(grouped) == Set(PlaceCategory.allCases))
        #expect(Set(PlaceCategory.allCases.map(\.label)).count == PlaceCategory.allCases.count)
    }

    @Test func searchMatchesLabelsAndKeywords() {
        func hits(_ q: String) -> Set<PlaceCategory> { Set(PlaceCategory.allCases.filter { $0.matches(q) }) }
        #expect(hits("arena").contains(.stadium))
        #expect(hits("concert").contains(.eventVenue))
        #expect(hits("Gallery").contains(.museum))
        #expect(hits("petrol").contains(.gasStation))
        #expect(hits("supermarket").contains(.grocery))
        #expect(hits("cafe").contains(.cafe))
        #expect(hits("café").contains(.cafe))
        #expect(hits("").count == PlaceCategory.allCases.count)
        #expect(hits("zzzz").isEmpty)
    }

    /// v_trips.purpose_final (SQL) must agree with PlaceCategory.defaultPurpose (Swift) for every category.
    @Test func viewPurposeMatchesSwiftDefault() throws {
        let store = try TravelStore.inMemory()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let place = Place(id: "p", coordinate: Philly.penn, radius: 80, source: .manual)
        try store.upsertPlace(place)
        try store.db.run("""
            INSERT INTO trips(id, departure_ts, arrival_ts, destination_place_id, source, user_status, deleted, created_at, updated_at)
            VALUES ('t', ?, ?, 'p', 'manual', 'manual', 0, ?, ?)
            """, now, now.addingTimeInterval(600), now, now)
        for c in PlaceCategory.allCases {
            var p = place
            p.category = c
            try store.upsertPlace(p)
            let got = try store.db.query("SELECT purpose_final FROM v_trips WHERE id = 't'").first?.string("purpose_final")
            #expect(got == c.defaultPurpose?.rawValue, "category \(c.rawValue)")
        }
    }

    /// A database created before #56 (schema v3, old view) upgrades and keeps its labels.
    @Test func upgradesLegacyDatabase() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hht-legacy-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try SQLiteConnection(path: path)
            for v in 0..<3 { try db.execute(Schema.migrations[v]); try db.setUserVersion(v + 1) }
            try db.run("""
                INSERT INTO places(id, name, lat, lon, radius_m, category, favorite, source, created_at, updated_at)
                VALUES ('old', 'Lab', 39.95, -75.19, 80, 'work_school', 0, 'manual', 0, 0)
                """)
        }
        let store = try TravelStore(path: path)
        #expect(store.schemaVersion == Schema.migrations.count)
        #expect(try store.place("old")?.category == .workSchool)
    }

    @Test func newCategoriesPersistAndExport() throws {
        let store = try TravelStore.inMemory()
        let added: [PlaceCategory] = [.stadium, .eventVenue, .museum, .library, .convenienceStore, .gasStation]
        for (i, c) in added.enumerated() {
            try store.upsertPlace(Place(id: "p\(i)", name: c.label, coordinate: Philly.penn, radius: 80, category: c, source: .manual))
        }
        for (i, c) in added.enumerated() { #expect(try store.place("p\(i)")?.category == c) }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-cat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try Exporter(store: store).exportBundle(to: dir)
        let csv = try String(contentsOf: folder.appendingPathComponent("places.csv"), encoding: .utf8)
        let geo = try String(contentsOf: folder.appendingPathComponent("places.geojson"), encoding: .utf8)
        let json = try String(contentsOf: folder.appendingPathComponent("data.json"), encoding: .utf8)
        for c in added {
            #expect(csv.contains(c.rawValue))
            #expect(geo.contains("\"\(c.rawValue)\""))
            #expect(json.contains("\"\(c.rawValue)\""))
        }
    }
}
