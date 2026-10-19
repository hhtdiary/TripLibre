import Foundation
import CoreLocation
import HHTCore

/// Optional reverse geocoding (Apple). Off by default: it sends the place coordinate to Apple.
/// Only fills address / city / region / country — never overwrites a user-entered value.
@MainActor
final class PlaceGeocoder {
    private let store: TravelStore
    private let geocoder = CLGeocoder()
    private var queue: [String] = []
    private var running = false

    init(store: TravelStore) { self.store = store }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "reverseGeocoding") }

    func enqueue(_ placeID: String) {
        guard Self.isEnabled else { return }
        queue.append(placeID)
        Task { await drain() }
    }

    /// Geocode every place that has no address yet.
    func backfill() {
        guard Self.isEnabled, let places = try? store.places() else { return }
        queue.append(contentsOf: places.filter { $0.address == nil && $0.city == nil }.map(\.id))
        Task { await drain() }
    }

    private func drain() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let p = try? store.place(id), p.address == nil || p.city == nil else { continue }
            let loc = CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude)
            guard let mark = try? await geocoder.reverseGeocodeLocation(loc).first else { continue }
            // `p` may be stale after the await (the user can edit meanwhile), so write only the empty
            // address columns instead of saving the whole record back.
            var street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
            if street.isEmpty { street = mark.name ?? "" }
            _ = try? store.fillMissingAddress(placeID: id, address: street, city: mark.locality,
                                              region: mark.administrativeArea, country: mark.isoCountryCode)
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // Apple rate-limits geocoding
        }
    }
}
