import SwiftUI
import HHTCore

/// The sample-day tutorial (issue #114): name a stop, give it a category and a purpose, correct a trip's mode, remove
/// a stop that inference made up, then read how tracking works and where it falls short. It draws the real diary rows and day map from `SampleDay`, which
/// lives in memory only, so nothing the learner does here is saved.
struct TutorialView: View {
    /// The last step's button: "Done" on a replay, "Continue" when the first-run welcome goes on after it.
    var finishLabel: LocalizedStringKey = "Done"
    var onFinish: () -> Void

    /// The real screen behind a sample diary row.
    enum RealTarget { case visit(String), trip(String) }

    /// An open real screen, with the model over its throwaway database (carried here so the sheet has it from the
    /// first frame).
    struct RealPage: Identifiable {
        let id = UUID()
        let target: RealTarget
        let model: AppModel
    }

    enum Step: Int, CaseIterable, Identifiable {
        case select, name, category, purpose, mode, phantom, limits, done
        var id: Int { rawValue }
    }

    @State private var step = Step.select
    @State private var sample = SampleDay()
    /// One of the app's real detail screens, open on the sample day in a throwaway in-memory database.
    @State private var realPage: RealPage?
    /// The page last shown, kept until it has closed and its edits are read back.
    @State private var closingPage: RealPage?
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private let day = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(spacing: 0) {
            header
            if typeSize.isAccessibilitySize {
                // large text: the coach card scrolls with the day instead of taking the screen
                stageScroll { coach; stage }
            } else {
                coach.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
                stageScroll { stage }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigation }
        .background(ToonBackground())
        .foregroundStyle(Toon.ink)
        .tint(Toon.accentDeep)
        .fontDesign(.rounded)
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: sample)
        .onChange(of: realPage?.id) { old, new in
            if new == nil, let page = closingPage, page.id == old { realPageClosed(page) }
            closingPage = realPage ?? closingPage
        }
        .sheet(item: $realPage) { page in
            switch page.target {
            case .visit(let id): VisitDetailView(visitID: id).environmentObject(page.model)
            case .trip(let id): TripDetailView(tripID: id).environmentObject(page.model)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: sample.phantomRemoved)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            ToonBadge(text: "Sample day", color: Toon.sun)
            HStack(spacing: 4) {
                ForEach(Step.allCases) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Toon.accent : Toon.ink.opacity(0.15)).frame(height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L("Step %lld of %lld", step.rawValue + 1, Step.allCases.count))
            Button("Skip") { onFinish() }
                .font(.toon(15)).foregroundStyle(Toon.ink).underline()
                .frame(minWidth: 44, minHeight: 44)
                .opacity(step == .done ? 0 : 1)
                .disabled(step == .done)
                .accessibilityHidden(step == .done)
                .accessibilityIdentifier("tutorialSkip")
        }
        .padding(.horizontal, 16)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            if step != .select {
                Button("Back") { go(Step(rawValue: step.rawValue - 1) ?? .select) }
                    .buttonStyle(ToonButtonStyle(height: 52, fontSize: 16, shadow: 4))
            }
            Button { next() } label: {
                Text(step == .done ? finishLabel : LocalizedStringKey("Next")).frame(maxWidth: .infinity)
            }
            .buttonStyle(ToonButtonStyle(fill: Toon.accent, height: 52, fontSize: 17, shadow: 4))
            .accessibilityIdentifier("tutorialNext")
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
        .background(Toon.ground.ignoresSafeArea(edges: .bottom))
    }

    private func stageScroll(@ViewBuilder _ content: () -> some View) -> some View {
        let content = content()
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) { content }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: step) { _, s in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    if let id = focusID(s) { proxy.scrollTo(id, anchor: .center) } else { proxy.scrollTo("top", anchor: .top) }
                }
            }
            .onChange(of: sample.phantomRemoved) { _, _ in
                // the row it was about is gone (or back): follow the highlight
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    if let id = focusID(step) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Pip's card

    private var coach: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Mascot(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.toon(19, .heavy)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    if let c = concept {
                        Text(c.question).font(.toon(13, .bold)).foregroundStyle(Toon.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let c = concept { ToonChip(symbol: c.symbol, color: c.color, size: 38) }
            }
            Text(message).font(.toon(14, .bold)).fixedSize(horizontal: false, vertical: true)
            controls
            if let path {
                Label(L("In your diary: %@", path), systemImage: "arrow.turn.down.right")
                    .font(.toon(12, .bold)).foregroundStyle(Toon.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let page = focusPage(step), step != .select {
                Button { openReal(page) } label: { Label("See the real page", systemImage: "rectangle.portrait.and.arrow.forward") }
                    .buttonStyle(ToonButtonStyle(fill: Toon.cream, height: 34, fontSize: 12, shadow: 2))
                    .accessibilityIdentifier("tutorialRealPage")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toonCard(radius: 22, shadow: 4)
        .id(step)
        .transition(.opacity)
    }

    private var concept: TutorialConcept? {
        switch step {
        case .name: return .name
        case .category: return .category
        case .purpose: return .purpose
        case .mode: return .mode
        default: return nil
        }
    }

    private var title: String {
        switch step {
        case .select: return L("Your day, rebuilt")
        case .phantom: return L("A stop that never was")
        case .limits: return L("How tracking works")
        case .done: return L("You've got it!")
        default: return concept?.title ?? ""
        }
    }

    private var message: String {
        switch step {
        case .select:
            return L("TripLibre turns where your iPhone goes into stops and the trips between them. The highlighted stop has no name yet. Tap it to see its real page, then tap Done to come back.")
        case .name:
            return L("You were at your friend Mingming's. Type what you call this place, or use my suggestion.")
        case .category:
            return L("A category belongs to the place: every visit here gets its icon and colour.")
        case .purpose:
            return L("A purpose belongs to one visit. The category suggests one, but the same place can mean a visit today and a pick-up tomorrow.")
        case .mode:
            return L("I guessed %@, but %@ in %@ is walking pace. A dashed card means I'm unsure: pick how you really travelled.",
                     SampleDay.guessedMode.localizedLabel, Fmt.distance(SampleDay.tripDistance), Fmt.duration(SampleDay.tripDuration))
        case .phantom:
            return sample.phantomRemoved
                ? L("Gone. The two walks are one trip again, in the list and on the map.")
                : L("On the walk home you waited at a crossing, and I took it for a stop. I get this wrong sometimes: tell me it wasn't one.")
        case .limits:
            return L("TripLibre records by itself in the background. Four things to keep in mind:")
        case .done:
            return L("Four labels, four different questions. This was a sample: nothing was saved to your diary or your exports.")
        }
    }

    /// Where the same edit is in the real diary.
    private var path: String? {
        let parts: [String]
        switch step {
        case .name: parts = [L("Visit"), L("Name this place")]
        case .category: parts = [L("Visit"), L("Name this place"), L("Category")]
        case .purpose: parts = [L("Visit"), L("Purpose")]
        case .mode: parts = [L("Trip"), L("Mode")]
        case .phantom: parts = [L("Visit"), L("This wasn't a stop")]
        default: return nil
        }
        return parts.joined(separator: " › ")
    }

    @ViewBuilder private var controls: some View {
        switch step {
        case .name:
            VStack(alignment: .leading, spacing: 8) {
                // A visible label, so the field keeps its name once the placeholder is gone.
                Text("Place name").font(.toon(13, .heavy)).foregroundStyle(Toon.muted)
                    .accessibilityHidden(true) // spoken as the field's label below
                TextField("Name", text: $sample.placeName)
                    .accessibilityLabel("Place name")
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
                    .font(.toon(17, .bold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .toonCard(Toon.cream, radius: 16, shadow: 0)
                    .accessibilityIdentifier("tutorialName")
                if sample.trimmedName != SampleDay.exampleName {
                    choice(SampleDay.exampleName, symbol: "sparkles", color: Toon.sun, selected: false) {
                        sample.placeName = SampleDay.exampleName
                        nameFocused = false
                    }
                }
            }
        case .category:
            ToonFlow {
                ForEach(SampleDay.categories) { c in
                    choice(c.localizedLabel, symbol: c.symbol, color: c.toonColor, selected: sample.category == c) { sample.category = c }
                }
            }
        case .purpose:
            ToonFlow {
                ForEach(SampleDay.purposes) { p in
                    choice(p.localizedLabel, symbol: nil, color: Toon.sky, selected: sample.shownPurpose == p) { sample.purpose = p }
                }
            }
        case .mode:
            ToonFlow {
                ForEach(SampleDay.modes) { m in
                    choice(m.localizedLabel, symbol: m.symbol, color: m.color, selected: sample.mode == m) { sample.mode = m }
                }
            }
        case .phantom:
            if sample.phantomRemoved {
                Button { sample.phantomRemoved = false } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(ToonButtonStyle(height: 38, fontSize: 13, shadow: 3))
                    .accessibilityIdentifier("tutorialUndoRemove")
            } else {
                Button { sample.phantomRemoved = true } label: { Label("This wasn't a stop", systemImage: "trash") }
                    .buttonStyle(ToonButtonStyle(fill: Toon.bubblegum, height: 42, fontSize: 14, shadow: 3))
                    .accessibilityIdentifier("tutorialRemoveStop")
            }
        default:
            EmptyView()
        }
    }

    /// A pill to pick: filled and ticked when chosen, so the choice doesn't rest on colour alone.
    private func choice(_ title: String, symbol: String?, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").fontWeight(.black).accessibilityHidden(true)
                } else if let symbol {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(ToonButtonStyle(fill: selected ? color : Toon.paper, height: 38, fontSize: 13, shadow: selected ? 1 : 3))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Stage

    @ViewBuilder private var stage: some View {
        switch step {
        case .limits: TrackingLimitsList().id("top")
        case .done: recap
        default: dayStage
        }
    }

    /// The diary row the step is about.
    private func focusID(_ s: Step) -> String? {
        switch s {
        case .select, .name, .category, .purpose: return "v-" + SampleDay.stopID
        case .mode: return "t-" + SampleDay.tripID
        case .phantom: return sample.phantomRemoved ? "t-" + SampleDay.returnTripID : "v-" + SampleDay.phantomID
        case .limits, .done: return nil
        }
    }

    /// The real screen for the row the step is about: the same one a tap on that row opens in the diary.
    private func focusPage(_ s: Step) -> RealTarget? {
        switch s {
        case .select, .name, .category, .purpose: return .visit(SampleDay.stopID)
        case .mode: return .trip(SampleDay.tripID)
        case .phantom: return sample.phantomRemoved ? nil : .visit(SampleDay.phantomID)
        case .limits, .done: return nil
        }
    }

    /// Opens a real detail screen on a fresh in-memory copy of the sample day as it stands now.
    private func openReal(_ target: RealTarget) {
        guard let store = try? TravelStore.inMemory(), (try? sample.seed(store, day: day)) != nil else { return }
        nameFocused = false
        realPage = RealPage(target: target, model: AppModel(sampleStore: store))
    }

    /// Whatever was changed on the real screen shows up in the tutorial; the throwaway database goes with the page.
    private func realPageClosed(_ page: RealPage) {
        sample.read(from: page.model.store)
        if step == .select { go(.name) }
    }

    private var dayStage: some View {
        let data = sample.data(on: day)
        let focus = focusID(step)
        return VStack(spacing: 10) {
            DayMap(data: data)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .toonCard(radius: 22, shadow: 4)
                .allowsHitTesting(false)   // it would trap the scroll; the list below is where the tutorial happens
                .accessibilityHidden(true)
                .id("top")
            ForEach(data.items) { item in
                let focused = item.id == focus
                stageRow(item)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background { if focused { FocusHalo() } }
                    .id(item.id)
            }
        }
    }

    @ViewBuilder private func stageRow(_ item: DiaryItem) -> some View {
        switch item {
        case .visit(let v, let p):
            // like in the diary, the row the step is about opens its real page
            if "v-" + v.id == focusID(step) {
                VisitRow(visit: v, place: p, day: day)
                    .detailRow(v.id == SampleDay.stopID ? "tutorialStop" : "tutorialPhantom", hint: "Opens the visit to correct it") {
                        openReal(.visit(v.id))
                    }
            } else {
                VisitRow(visit: v, place: p, day: day).accessibilityElement(children: .combine)
            }
        case .trip(let t):
            if step == .mode && t.id == SampleDay.tripID {
                TripRow(trip: t, quickModes: SampleDay.modes, day: day) { sample.mode = $0 }
                    .detailRow("tutorialTrip", hint: "Opens the trip to correct it") { openReal(.trip(t.id)) }
            } else {
                TripRow(trip: t, quickModes: SampleDay.modes, day: day) { _ in }.allowsHitTesting(false)
            }
        default:
            EmptyView()
        }
    }

    /// The four labels side by side, with what the learner chose, then the finished rows.
    private var recap: some View {
        let data = sample.data(on: day)
        return VStack(spacing: 16) {
            StickerGrid {
                ForEach(Array(TutorialConcept.allCases.enumerated()), id: \.offset) { i, c in
                    ConceptTile(concept: c, value: value(of: c), tilt: [-1.5, 1.5, 1, -1][i % 4])
                }
            }
            .padding(.top, 4)
            .id("top")
            ForEach(data.items.filter { $0.id == "t-" + SampleDay.tripID || $0.id == "v-" + SampleDay.stopID }) { item in
                stageRow(item).allowsHitTesting(false)
            }
        }
    }

    private func value(of c: TutorialConcept) -> String {
        switch c {
        case .name: return sample.trimmedName.isEmpty ? SampleDay.exampleName : sample.trimmedName
        case .category: return (sample.category ?? SampleDay.exampleCategory).localizedLabel
        case .purpose: return (sample.shownPurpose ?? SampleDay.examplePurpose).localizedLabel
        case .mode: return (sample.mode ?? SampleDay.exampleMode).localizedLabel
        }
    }

    // MARK: - Moving on

    private func go(_ to: Step) {
        nameFocused = false
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { step = to }
        titleFocused = true
    }

    /// Next never blocks: a step left untouched is filled in with the example answer, so the day still tells its story.
    private func next() {
        switch step {
        case .name: if sample.trimmedName.isEmpty { sample.placeName = SampleDay.exampleName }
        case .category: if sample.category == nil { sample.category = SampleDay.exampleCategory }
        case .purpose: if sample.purpose == nil { sample.purpose = sample.shownPurpose ?? SampleDay.examplePurpose }
        case .mode: if sample.mode == nil { sample.mode = SampleDay.exampleMode }
        case .phantom: sample.phantomRemoved = true
        case .done:
            onFinish()
            return
        case .select, .limits: break
        }
        go(Step(rawValue: step.rawValue + 1) ?? .done)
    }
}

/// The four things a diary entry can be labelled with. People mix them up (issue #114), so each has its own question.
enum TutorialConcept: CaseIterable {
    case name, category, purpose, mode

    var title: String {
        switch self {
        case .name: return L("Place name")
        case .category: return L("Place category")
        case .purpose: return L("Trip purpose")
        case .mode: return L("Travel mode")
        }
    }

    var question: String {
        switch self {
        case .name: return L("What you call it")
        case .category: return L("What kind of place it is")
        case .purpose: return L("Why you went, this time")
        case .mode: return L("How you got there")
        }
    }

    var symbol: String {
        switch self {
        case .name: return "character.cursor.ibeam"
        case .category: return "square.grid.2x2.fill"
        case .purpose: return "flag.fill"
        case .mode: return "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .name: return Toon.sun
        case .category: return Toon.mint
        case .purpose: return Toon.sky
        case .mode: return Toon.lime
        }
    }
}

private struct ConceptTile: View {
    let concept: TutorialConcept
    let value: String
    var tilt: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(concept.title, systemImage: concept.symbol).font(.toon(12, .black))
            Text(value).font(.toon(19, .bold)).toonLineLimit(2, minScale: 0.7)
            Text(concept.question).font(.toon(12, .bold)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Toon.ink)
        // combined before the card is added, like StatSticker: the contrast audit then measures the text's own frame
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // both tiles of a row as tall as the taller
        .padding(.horizontal, 12).padding(.vertical, 10)
        .toonCard(concept.color, radius: 18, shadow: 4)
        .tilt(tilt)
    }
}

/// A soft, breathing highlight behind the diary row the current step is about.
private struct FocusHalo: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        shape.fill(Toon.sun.opacity(on ? 0.5 : 0.28))
            .overlay(shape.strokeBorder(Toon.accent, style: StrokeStyle(lineWidth: 3, dash: [9, 6])))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - How tracking works

/// What automatic tracking needs and where it falls short (issue #114), in the app instead of only in the docs.
/// The tutorial's sixth step, and Settings › Help.
struct TrackingLimitsList: View {
    var body: some View {
        VStack(spacing: 14) {
            limit("location.fill", Toon.sky, "Allow “Always”",
                  "Background recording needs it. With “While Using” only, trips made while the app is closed can be missed.", -1)
            limit("moon.zzz.fill", Toon.grape, "Days can have gaps",
                  "If the iPhone is off, has no signal, or iOS stops the app in the background, part of a day can go missing. You can correct the diary afterwards.", 1)
            limit("scope", Toon.bubblegum, "GPS drifts",
                  "Indoors and between tall buildings a stop can land a street away, or a short trip can appear that never happened. Move it or remove it.", -1)
            limit("questionmark.circle.fill", Toon.lime, "Modes are guesses",
                  "A slow car, a bus and a bike can look alike to a phone. Trips I'm unsure about ask you to check.", 1)
        }
    }

    private func limit(_ symbol: String, _ color: Color, _ title: LocalizedStringKey, _ text: LocalizedStringKey, _ tilt: Double) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ToonChip(symbol: symbol, color: color, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.toon(16, .heavy))
                Text(text).font(.toon(13, .bold)).foregroundStyle(Toon.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Toon.ink)
        .padding(12)
        .toonCard(radius: 20)
        .tilt(tilt)
    }
}

/// `TrackingLimitsList` as a sheet of its own.
struct TrackingHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MascotSays(text: L("TripLibre records by itself in the background. Four things to keep in mind:"))
                    TrackingLimitsList()
                }
                .padding(20)
            }
            .background(ToonBackground())
            .navigationTitle("How tracking works")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.confirmTint() } }
        }
    }
}

/// One line of in-context help above the diary rows, for people who skipped the tutorial or installed before it
/// existed: what tapping a row does, and a way into the sample day.
struct DiaryTipCard: View {
    var onShow: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ToonRowStack(alignment: .top) {
            ToonChip(symbol: "hand.tap.fill", color: Toon.sun, size: 44)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading) {
                    Text("Tap a stop to name it. Tap a trip to fix how you travelled.")
                        .font(.toon(14, .heavy)).foregroundStyle(Toon.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                ToonFlow {
                    Button("Show me", action: onShow)
                        .buttonStyle(ToonButtonStyle(fill: Toon.accent, height: 34, fontSize: 12, shadow: 2))
                        .accessibilityIdentifier("diaryTipShow")
                    Button("Got it", action: onDismiss)
                        .buttonStyle(ToonButtonStyle(height: 34, fontSize: 12, shadow: 2))
                        .accessibilityIdentifier("diaryTipDismiss")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .toonCard(Toon.cream, radius: 18, shadow: 0, dashed: true)
    }
}
