import SwiftUI
import HHTCore

/// A finished stop whose place is still a guess among the user's saved places nearby (issue #116).
struct PlaceReview: Identifiable {
    var visit: Visit
    /// The place inference matched, if any.
    var place: Place?
    /// The user's saved places near the stop, nearest first (`PlaceRecall`).
    var candidates: [PlaceRecall.Candidate]
    var id: String { visit.id }

    /// The day's visits that need their place confirmed, newest first. Skipped visits are left out; skipping never
    /// confirms anything, so the visit can still be corrected from its detail screen.
    static func load(_ store: TravelStore, visits: [Visit], places: [String: Place], radius: Double,
                     skipped: Set<String>) -> [PlaceReview] {
        visits.compactMap { v in
            guard !skipped.contains(v.id), v.placeStatus == .auto, v.departure != nil else { return nil }
            let c = (try? store.recallCandidates(near: v.coordinate, radius: radius)) ?? []
            guard PlaceRecall.needsReview(v, candidates: c) else { return nil }
            return PlaceReview(visit: v, place: v.placeID.flatMap { places[$0] }, candidates: c)
        }
        .sorted { $0.visit.arrival > $1.visit.arrival }
    }
}

/// Pip asks which saved place a stop was: one tap on a nearby saved place confirms it, "None of these" leaves the stop
/// unspecified, and "Choose or create…" opens the full picker. The Visit screen keeps the full editing (issue #116).
struct PlaceReviewCard: View {
    /// grows with the icon inside it
    @ScaledMetric(relativeTo: .footnote) private var closeTarget: CGFloat = 32
    @EnvironmentObject var model: AppModel
    let review: PlaceReview
    /// Others waiting besides this one; shows "More to check" when above zero.
    var more = 0
    var onMore: () -> Void = {}
    @State private var showPicker = false
    @State private var saved = 0

    /// At most this many saved places as one-tap buttons; the picker has the rest.
    private static let shown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ToonChip(symbol: "mappin.and.ellipse", color: Toon.grape, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Which place was this?")).font(.toon(15, .heavy))
                    Text(subtitle).font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                }
                Spacer(minLength: 0)
                Button { model.skipPlaceReview(review.id) } label: {
                    Image(systemName: "xmark").font(.toon(13, .black)).foregroundStyle(Toon.muted)
                        .frame(width: closeTarget, height: closeTarget).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Don't ask about this visit"))
            }
            .foregroundStyle(Toon.ink)
            ToonFlow(spacing: 6) {
                ForEach(review.candidates.prefix(Self.shown)) { c in
                    let text = "\(c.place.displayName) · \(Fmt.distance(c.distance))"
                    Button {
                        model.perform { try model.edit.setVisitPlace(review.id, placeID: c.id) }
                        saved += 1
                    } label: {
                        Label(text, systemImage: c.place.category?.symbol ?? "mappin")
                    }
                    .buttonStyle(ToonButtonStyle(fill: c.place.category?.toonColor ?? Toon.paper, height: 34, fontSize: 13, shadow: 2))
                    .accessibilityLabel(c.place.displayName)
                    .accessibilityValue(L("%@ away", Fmt.distance(c.distance)))
                    .accessibilityHint(L("Confirms this place for the stop"))
                }
                Button(L("None of these")) { // a11y-check:disable duplicate-button-label (also on the Visit screen, never beside it)
                    model.perform { try model.edit.setVisitPlaceUnspecified(review.id) }
                    saved += 1
                }
                .buttonStyle(ToonButtonStyle(height: 34, fontSize: 13, shadow: 2))
                Button { showPicker = true } label: { Label(L("Choose or create…"), systemImage: "plus") }
                    .buttonStyle(ToonButtonStyle(height: 34, fontSize: 13, shadow: 2))
                    .accessibilityIdentifier("placeReviewChoose")
            }
            if more > 0 {
                Button(action: onMore) {
                    Label(L("More to check (%lld)", more), systemImage: "list.bullet")
                        .font(.toon(13, .heavy)).foregroundStyle(Toon.ink)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("placeReviewMore")
            }
        }
        .padding(12)
        .toonCard(Toon.cream, radius: 18, shadow: 0, dashed: true)
        .sensoryFeedback(.success, trigger: saved)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("placeReview")
        .sheet(isPresented: $showPicker) {
            PlacePickerView(near: review.visit.coordinate) { choice in
                switch choice {
                case .existing(let id): model.perform { try model.edit.setVisitPlace(review.id, placeID: id) }
                case .new(let name, let cat, let custom):
                    model.perform { try model.edit.createPlace(forVisit: review.id, name: name, category: cat, customCategory: custom) }
                }
            }
            .environmentObject(model)
        }
    }

    private var subtitle: String {
        let v = review.visit
        let when = "\(Fmt.time(v.arrival, tz: v.timeZone))–\(Fmt.time(v.departure ?? Date(), tz: v.timeZone))"
        guard let p = review.place, p.isNamed else { return when }
        return when + " · " + L("Guessed: %@", p.displayName)
    }
}

/// Every stop of the day still waiting for its place, one card each (from "More to check" on Today).
struct PlaceReviewList: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let reviews: [PlaceReview]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(reviews) { r in PlaceReviewCard(review: r).toonRow(top: 4, bottom: 6) }
                } footer: {
                    Text(L("Only places you saved, found on this iPhone. Nothing is picked for you; the detected stop stays as recorded."))
                        .toonSectionText()
                }
            }
            .groupedList()
            .navigationTitle(L("Places to check"))
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.confirmTint() } }
            .onChange(of: reviews.isEmpty) { _, empty in if empty { dismiss() } }
        }
    }
}
