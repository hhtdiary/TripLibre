import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import HHTCore

/// Colours for the diary agent: a quieter navy-and-amber look than the sticker screens, light and dark.
enum AgentTheme {
    static let ground = dyn(0xF4F6FA, 0x0B1730)
    static let bar = dyn(0xFFFFFF, 0x0B1730)
    static let surface = dyn(0xFFFFFF, 0x13254A)
    static let border = dyn(0xDDE4EF, 0x22396A)
    static let hairline = dyn(0xDDE4EF, 0x1D2F52)
    static let chip = dyn(0xE8EDF5, 0x1D3460)
    static let chipBorder = dyn(0xC9D3E3, 0x2D4677)
    static let field = dyn(0xF4F6FA, 0x10203F)
    static let ink = dyn(0x0F1F3A, 0xEEF2F8)
    static let muted = dyn(0x4F6180, 0x9FB0C8)
    static let body = dyn(0x33435F, 0xC9D4E4)
    static let green = dyn(0x1C7A58, 0x5AC8A0)        // ≥ 4.5:1 on ground and surface in both modes
    static let amberText = dyn(0x8F5200, 0xF4A93B)
    static let amberWash = dyn(0xFFF4E3, 0x13254A)
    static let amber = Color(hex: 0xF4A93B)
    static let onAmber = Color(hex: 0x0F1F3A)
    static let strong = dyn(0x0F1F3A, 0xF4A93B)       // primary buttons and the user's own messages
    static let onStrong = dyn(0xFFFFFF, 0x0B1730)
    static let successWash = dyn(0xE1F4EC, 0x123A3A)
    static let successText = dyn(0x135C42, 0xBDF0DC)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
        Color(hex: light)
        #endif
    }
}

private typealias A = AgentTheme

/// The diary agent: recaps the day, asks about stops it can't explain, proposes mode fixes,
/// and answers questions about the diary. All of it runs on this iPhone (see `DiaryAgent`).
struct AgentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tabBarSpace) private var tabBarSpace
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var data = DayData()
    @State private var asking: [Visit] = []
    @State private var proposals: [DiaryAgent.ModeProposal] = []
    @State private var answered: [Recalled] = []
    @State private var turns: [Exchange] = []
    @State private var question = ""
    @FocusState private var inputFocused: Bool

    struct Recalled: Identifiable { let id: String; let stop: String; let purpose: TripPurpose }
    struct Exchange: Identifiable { let id = UUID(); let question: String; let answer: DiaryAgent.Answer? }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(dateLine).font(.system(size: 11, design: .monospaced)).tracking(0.6)
                            .foregroundStyle(A.muted).frame(maxWidth: .infinity)
                        summary
                        ForEach(answered) { r in
                            UserBubble(text: r.purpose.label)
                            AgentSays {
                                Text("Saved: the \(r.stop) stop was \(r.purpose.label.lowercased()). It's locked against rebuilds.")
                            }
                        }
                        if let v = asking.first { recall(v) }
                        if let p = proposals.first { proposal(p) }
                        ForEach(turns) { t in
                            UserBubble(text: t.question)
                            AgentAnswerView(answer: t.answer, ask: ask)
                        }
                        if turns.isEmpty { suggestions }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .contentMargins(.bottom, 0, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            inputBar
        }
        .background(A.ground.ignoresSafeArea())
        .foregroundStyle(A.ink)
        .fontDesign(.default)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.revision) { load() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(A.amber)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0F1F3A)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Diary agent").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(A.green).frame(width: 7, height: 7)
                    Text("On-device · nothing leaves your phone").font(.system(size: 12)).foregroundStyle(A.muted)
                }
            }
            Spacer(minLength: 0)
            NavigationLink { DayView(day: day, fixedDay: true) } label: {
                Image(systemName: "calendar").font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(A.hairline))
            }
            .foregroundStyle(A.ink)
            .accessibilityLabel("Open this day in the diary")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(A.bar.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { A.hairline.frame(height: 1) }
    }

    @ViewBuilder private var summary: some View {
        let askingIDs = Set(asking.map(\.id))
        let s = DiaryAgent.summarize(visits: data.visits, trips: data.trips, places: data.places, asking: askingIDs) { v in
            let at = Fmt.time(v.arrival, tz: v.timeZone)
            if askingIDs.contains(v.id) { return "? " + at }
            return v.placeID.flatMap { data.places[$0]?.address } ?? "Stop \(at)"
        }
        let open = asking.count + proposals.count
        if s.chain.isEmpty {
            AgentSays { Text("Nothing is recorded yet. I'll recap your day once you've been somewhere. You can still ask about earlier days below.") }
        } else {
            AgentSays {
                (s.trips == 0
                    ? Text("No trips \(isToday ? "yet today" : "that day"), just \(s.places == 1 ? "one stop" : "\(s.places) stops"). ")
                    : Text("I rebuilt \(isToday ? "your day" : Fmt.shortDay(day)): **\(s.trips) \(s.trips == 1 ? "trip" : "trips")** between **\(s.places) \(s.places == 1 ? "place" : "places")**. "))
                    + Text(open == 0 ? "Everything is reviewed." : "\(open == 1 ? "One thing needs" : "\(open) things need") a quick look.")
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(isToday ? "Today's chain" : "The day's chain").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(Fmt.distance(s.distance)).font(.system(size: 11, design: .monospaced)).foregroundStyle(A.muted)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(Array(s.chain.enumerated()), id: \.offset) { _, step in chainStep(step) }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(A.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(A.border))
            }
        }
    }

    @ViewBuilder private func chainStep(_ step: DiaryAgent.ChainStep) -> some View {
        switch step {
        case .stop(let label, let asking):
            Text(label).font(.system(size: 12)).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(asking == nil ? A.ink : A.amberText)
                .background {
                    if asking == nil {
                        RoundedRectangle(cornerRadius: 8).fill(A.chip)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(A.amberWash)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(A.amberText, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                }
        case .leg(let mode):
            Text(mode.label.lowercased()).font(.system(size: 12)).foregroundStyle(A.green).padding(.vertical, 4)
        }
    }

    private func recall(_ v: Visit) -> some View {
        let place = v.placeID.flatMap { data.places[$0] }
        let near = place?.address.map { " near \($0)" } ?? ""
        let at = Fmt.time(v.arrival, tz: v.timeZone)
        return AgentSays {
            Text("You stopped **\(Fmt.duration(v.duration()))**\(near) at \(at). What was it?")
            FlowLayout(spacing: 8) {
                ForEach(DiaryAgent.recallChoices) { p in
                    Button(p.label) { answer(v, p, stop: at) }.buttonStyle(AgentChipStyle())
                }
            }
            Button("Skip this stop") { model.perform { try model.edit.confirm(visitID: v.id) } }
                .font(.system(size: 14)).foregroundStyle(A.muted).frame(minHeight: 44)
        }
    }

    private func proposal(_ p: DiaryAgent.ModeProposal) -> some View {
        let t = data.trips.first { $0.id == p.tripID }
        let when = t.map { Fmt.time($0.departure, tz: $0.timeZone) } ?? ""
        return AgentSays {
            if let m = p.proposed {
                Text("The \(when) trip looks like **\(m.label.lowercased())**, not \(p.current.label.lowercased()).")
            } else {
                Text("I couldn't tell how you made the \(when) trip.")
            }
            if proposals.count > 1 {
                Text("\(proposals.count - 1) more after this one.").font(.system(size: 13)).foregroundStyle(A.muted)
            }
            NavigationLink { AgentCorrectionView(proposal: p) } label: {
                HStack(spacing: 8) {
                    Text(p.proposed == nil ? "Pick the mode" : "Review the change")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(A.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(A.border))
            }
            .foregroundStyle(A.ink)
        }
    }

    private var suggestions: some View {
        AgentSays {
            Text("Ask me about your diary, for example:")
            FlowLayout(spacing: 8) {
                ForEach(AgentAnswerView.examples, id: \.self) { q in
                    Button(q) { ask(q) }.buttonStyle(AgentChipStyle())
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your trips, modes or places", text: $question)
                .font(.system(size: 15))
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit { ask(question) }
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(Capsule().fill(A.field))
                .overlay(Capsule().strokeBorder(A.chipBorder))
                .accessibilityLabel("Ask your diary")
            Button { ask(question) } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(A.onAmber)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(A.amber))
            }
            .accessibilityLabel("Send")
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10 + tabBarSpace)
        .background(A.bar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { A.hairline.frame(height: 1) }
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = isToday ? "EEE d MMM · HH:mm" : "EEE d MMM yyyy"
        return f.string(from: isToday ? Date() : day).uppercased()
    }

    // MARK: - Actions

    /// Today, or the most recent day with trips (within a month) while today has none yet.
    private func load() {
        let store = model.store
        let now = Date()
        var shown = Calendar.current.startOfDay(for: now)
        var d = DayData.load(store, day: shown)
        if d.trips.isEmpty,
           let last = (try? store.trips(overlapping: now.addingTimeInterval(-30 * 86_400), now, withSegments: false))?.last {
            shown = Calendar.current.startOfDay(for: last.departure)
            d = DayData.load(store, day: shown)
        }
        day = shown
        data = d
        asking = DiaryAgent.recallCandidates(visits: d.visits, places: d.places)
        let placeOf = Dictionary(d.visits.map { ($0.id, $0.placeID) }, uniquingKeysWith: { a, _ in a })
        proposals = d.trips.compactMap { t in
            var history: [TravelMode] = []
            if let o = t.originVisitID.flatMap({ placeOf[$0] ?? (try? store.visit($0))?.placeID }),
               let dst = t.destinationVisitID.flatMap({ placeOf[$0] ?? (try? store.visit($0))?.placeID }) {
                history = (try? store.correctedModes(originPlaceID: o, destinationPlaceID: dst)) ?? []
            }
            return DiaryAgent.modeProposal(for: t, history: history)
        }
    }

    private func answer(_ v: Visit, _ p: TripPurpose, stop: String) {
        model.perform { try model.edit.setVisitPurpose(v.id, p) }
        answered.append(Recalled(id: v.id, stop: stop, purpose: p))
    }

    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        inputFocused = false
        let a = DiaryAgent.topic(for: q).flatMap { try? DiaryAgent.answer($0, store: model.store) }
        turns.append(Exchange(question: q, answer: a))
    }
}

// MARK: - Answers

/// The agent's reply to a question: what it read, then the answer and a small chart.
struct AgentAnswerView: View {
    let answer: DiaryAgent.Answer?
    let ask: (String) -> Void

    static let examples = ["How do I get around?", "How far do I travel?", "Where do I spend my time?", "How many trips do I make?"]

    var body: some View {
        if let a = answer {
            VStack(alignment: .leading, spacing: 14) {
                steps(a)
                AgentSays { reply(a) }
            }
        } else {
            AgentSays {
                Text("I can only answer questions about how you get around, how far you travel, how many trips you make and where you spend your time. Try one of these:")
                FlowLayout(spacing: 8) {
                    ForEach(Self.examples, id: \.self) { q in Button(q) { ask(q) }.buttonStyle(AgentChipStyle()) }
                }
            }
        }
    }

    private func steps(_ a: DiaryAgent.Answer) -> some View {
        let what: String = switch a.topic {
        case .modeShare: "Computed mode share by trips"
        case .distance: "Added up distance travelled"
        case .trips: "Counted trips per recorded day"
        case .places: "Ranked places by time spent"
        }
        return VStack(alignment: .leading, spacing: 6) {
            step("Read the last \(a.days) days · \(a.current.trips) trips")
            step("Compared with the \(a.days) days before · \(a.previous.trips) trips")
            step(what)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(A.muted)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(A.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(A.hairline))
        .accessibilityElement(children: .combine)
    }

    private func step(_ s: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(A.green)
                .accessibilityHidden(true)
            Text(s)
        }
    }

    @ViewBuilder private func reply(_ a: DiaryAgent.Answer) -> some View {
        let cur = a.current, prev = a.previous
        if cur.trips == 0 && a.topic != .places || a.topic == .places && cur.topPlaces.isEmpty {
            Text("I don't have anything from the last \(a.days) days yet.")
        } else {
            switch a.topic {
            case .modeShare: modeShare(a)
            case .distance:
                Text("You travelled **\(Fmt.distance(cur.totalDistance))** in the last \(a.days) days, about \(Fmt.distance(cur.distancePerDay)) per recorded day")
                    + Text(prev.trips > 0 ? ", compared with \(Fmt.distance(prev.totalDistance)) the \(a.days) days before." : ".")
                comparison(prev: prev.totalDistance, cur: cur.totalDistance, label: Fmt.distance)
            case .trips:
                Text("You made **\(cur.trips) trips** in the last \(a.days) days, \(String(format: "%.1f", cur.tripsPerDay)) per recorded day")
                    + Text(prev.trips > 0 ? ", compared with \(prev.trips) the \(a.days) days before." : ".")
                comparison(prev: Double(prev.trips), cur: Double(cur.trips), label: { String(Int($0)) })
            case .places:
                let top = cur.topPlaces.prefix(3)
                if let first = top.first {
                    Text("You spent the most time at **\(first.name)**: \(Fmt.hours(first.dwell)) over \(first.visits) visits.")
                }
                card(title: "Most time, last \(a.days) days") {
                    ForEach(Array(top)) { p in
                        HStack {
                            Text(p.name).font(.system(size: 14)).lineLimit(1)
                            Spacer()
                            Text(Fmt.hours(p.dwell)).font(.system(size: 12, design: .monospaced)).foregroundStyle(A.muted)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func modeShare(_ a: DiaryAgent.Answer) -> some View {
        let cur = a.current.groupShareByTrips, prev = a.previous.groupShareByTrips
        let pct = { (x: Double) in "\(Int((x * 100).rounded()))%" }
        if let top = cur.max(by: { $0.value < $1.value }) {
            Text("**\(pct(top.value))** of your trips in the last \(a.days) days were \(top.key.label.lowercased())")
                + Text(a.previous.trips > 0 ? ", compared with \(pct(prev[top.key] ?? 0)) the \(a.days) days before." : ".")
        }
        card(title: "Mode share by trips") {
            shareBar("PREV", prev, pct: pct)
            shareBar("LAST \(a.days) D", cur, pct: pct)
            FlowLayout(spacing: 12) {
                ForEach(ModeGroup.allCases.filter { (cur[$0] ?? 0) + (prev[$0] ?? 0) > 0 }, id: \.self) { g in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(g.color).frame(width: 10, height: 10)
                        Text(g.label).font(.system(size: 12)).foregroundStyle(A.body)
                    }
                }
            }
        }
    }

    private func shareBar(_ label: String, _ share: [ModeGroup: Double], pct: @escaping (Double) -> String) -> some View {
        let parts = ModeGroup.allCases.compactMap { g in share[g].flatMap { $0 > 0 ? (g, $0) : nil } }
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(A.muted)
            if parts.isEmpty {
                Text("no trips").font(.system(size: 12)).foregroundStyle(A.muted)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.0) { g, x in
                            g.color.frame(width: max(2, (geo.size.width - CGFloat(parts.count - 1) * 2) * x))
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ": " + (parts.isEmpty ? "no trips" : parts.map { "\($0.0.label) \(pct($0.1))" }.joined(separator: ", ")))
    }

    private func comparison(prev: Double, cur: Double, label: @escaping (Double) -> String) -> some View {
        let top = max(prev, cur, 1)
        return card(title: "Last 30 days vs the 30 before") {
            ForEach([("PREV", prev, A.chipBorder), ("LAST", cur, A.amber)], id: \.0) { name, v, color in
                HStack(spacing: 10) {
                    Text(name).font(.system(size: 11, design: .monospaced)).foregroundStyle(A.muted).frame(width: 40, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: max(2, geo.size.width * v / top))
                    }
                    .frame(height: 14)
                    Text(label(v)).font(.system(size: 12, design: .monospaced)).frame(minWidth: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name == "PREV" ? "Previous 30 days" : "Last 30 days"): \(label(v))")
            }
        }
    }

    private func card<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(A.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(A.border))
    }
}

// MARK: - Correction

/// One proposed mode fix: the route, the agent's reasons, and accept / pick / keep.
struct AgentCorrectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tabBarSpace) private var tabBarSpace
    let proposal: DiaryAgent.ModeProposal
    @State private var trip: Trip?
    @State private var origin: Place?
    @State private var destination: Place?
    @State private var modes: [TravelMode] = []
    @State private var result: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let t = trip {
                    TripMap(trip: t, origin: origin?.coordinate, destination: destination?.coordinate)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(A.hairline))
                    Text("\(origin?.displayName ?? "Unknown origin") → \(destination?.displayName ?? "Unknown destination") · \(Fmt.distance(t.distance))")
                        .font(.system(size: 13)).foregroundStyle(A.muted)
                }
                Group {
                    if let m = proposal.proposed {
                        Text("I recorded this as **\(proposal.current.label.lowercased())**, but it looks like **\(m.label.lowercased())**:")
                    } else {
                        Text("I recorded this as **\(proposal.current.label.lowercased())**, but I'm not sure:")
                    }
                }
                .font(.system(size: 15)).lineSpacing(3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(proposal.reasons.enumerated()), id: \.offset) { i, r in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", i + 1)).font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(A.green).frame(width: 22, alignment: .leading)
                            Text(Self.text(r)).font(.system(size: 14)).foregroundStyle(A.body)
                        }
                    }
                }
                changeCard
                if let result {
                    Label(result, systemImage: "checkmark")
                        .font(.system(size: 14)).foregroundStyle(A.successText)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(A.successWash))
                }
            }
            .padding(16)
        }
        .contentMargins(.bottom, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) { buttons }
        .background(A.ground.ignoresSafeArea())
        .foregroundStyle(A.ink)
        .fontDesign(.default)
        .navigationTitle(trip.map { "Trip · \(Fmt.time($0.departure, tz: $0.timeZone)) → \(Fmt.time($0.arrival, tz: $0.timeZone))" } ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.revision) { load() }
    }

    private var changeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHANGE").font(.system(size: 11, design: .monospaced)).tracking(0.6).foregroundStyle(A.muted)
                .padding(.horizontal, 14).padding(.vertical, 10)
            A.border.frame(height: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now").font(.system(size: 12)).foregroundStyle(A.muted)
                    Text(proposal.current.label).font(.system(size: 17, weight: .semibold)).strikethrough(proposal.proposed != nil)
                        .foregroundStyle(proposal.proposed != nil ? A.muted : A.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                A.border.frame(width: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Proposed").font(.system(size: 12)).foregroundStyle(A.muted)
                    Text(proposal.proposed?.label ?? "Your pick").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(proposal.proposed == nil ? A.muted : A.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(A.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(A.border))
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if let m = proposal.proposed {
                Button { setMode(m) } label: {
                    Text("Accept and lock").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(A.onStrong).background(RoundedRectangle(cornerRadius: 14).fill(A.strong))
                }
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(modes) { m in
                        Button { setMode(m) } label: { Label(m.label, systemImage: m.symbol) }
                    }
                } label: {
                    secondary(proposal.proposed == nil ? "Pick the mode" : "Pick another mode")
                }
                Button {
                    model.perform { try model.edit.confirm(tripID: proposal.tripID) }
                    result = "Kept as \(proposal.current.label.lowercased()). I won't ask about this trip again."
                } label: { secondary("Keep \(proposal.current.label.lowercased())") }
            }
        }
        .disabled(result != nil)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10 + tabBarSpace)
        .background(A.bar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { A.hairline.frame(height: 1) }
    }

    private func secondary(_ title: String) -> some View {
        Text(title).font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(A.ink)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(A.chipBorder))
            .contentShape(Rectangle())
    }

    private func setMode(_ m: TravelMode) {
        model.perform { try model.edit.setTripMode(proposal.tripID, m) }
        result = "Changed to \(m.label.lowercased()) and locked against rebuilds."
    }

    private func load() {
        let store = model.store
        guard let t = try? store.trip(proposal.tripID) else { return }
        trip = t
        let ov = t.originVisitID.flatMap { try? store.visit($0) }, dv = t.destinationVisitID.flatMap { try? store.visit($0) }
        origin = (ov?.placeID ?? t.originPlaceID).flatMap { try? store.place($0) }
        destination = (dv?.placeID ?? t.destinationPlaceID).flatMap { try? store.place($0) }
        let frequent = (try? store.frequentModes(limit: 4)) ?? []
        modes = frequent + TravelMode.allCases.filter { $0 != .unknown && !frequent.contains($0) }
    }

    static func text(_ r: DiaryAgent.Reason) -> String {
        switch r {
        case .habit(let m, let n, let of):
            return "You chose \(m.label.lowercased()) on \(n) of your last \(of) corrected trips between these places"
        case .averageSpeed(let v):
            return Fmt.usesMetric ? String(format: "Average speed %.0f km/h", v * 3.6) : String(format: "Average speed %.0f mph", v * 2.23694)
        case .lowConfidence(let c):
            return c.map { "The automatic guess was only \(Int(($0 * 100).rounded()))% sure" } ?? "The automatic guess couldn't tell the mode"
        }
    }
}

// MARK: - Shared bits

/// A message from the agent: plain text on the ground, no bubble, so data cards can sit inside it.
private struct AgentSays<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .font(.system(size: 15))
            .lineSpacing(3)
            .frame(maxWidth: 340, alignment: .leading)
    }
}

private struct UserBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(A.onStrong)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                               bottomTrailingRadius: 4, topTrailingRadius: 18).fill(A.strong))
            .frame(maxWidth: 280, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct AgentChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(configuration.isPressed ? A.onAmber : A.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(configuration.isPressed ? A.amber : A.surface))
            .overlay(Capsule().strokeBorder(configuration.isPressed ? A.amber : A.chipBorder))
    }
}
