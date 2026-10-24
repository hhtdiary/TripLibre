import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import HHTCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab = UserDefaults.standard.integer(forKey: "hhtTab")
    @State private var keyboardUp = false
    /// The agent's conversation lives for the session once opened, so switching tabs doesn't wipe it.
    @State private var agentOpened = false
    /// The agent is opt-in (Settings › Experimental); while off, its tab doesn't exist.
    @AppStorage("agentEnabled") private var agentEnabled = false
    /// The last system tab, kept on screen under the agent.
    @State private var lastTab = 0
    /// Bumped to pop Today back to its root, so a Stamp widget tap lands where its confirmation and Undo show.
    @State private var todayStack = 0

    /// iPhone tab bars show at most five tabs and move the rest into a "More" list, so the agent (tag 5)
    /// sits over the TabView instead of inside it.
    private static let agentTag = 5

    var body: some View {
        TabView(selection: Binding(get: { tab == Self.agentTag ? lastTab : tab }, set: { tab = $0 })) {
            NavigationStack { DayView() }.id(todayStack).tabBarSpace(!keyboardUp).tag(0)
            NavigationStack { HistoryView() }.tabBarSpace(!keyboardUp).tag(1)
            NavigationStack { ExploreMapView() }.tabBarSpace(!keyboardUp).tag(2)
            NavigationStack { StatsView() }.tabBarSpace(!keyboardUp).tag(3)
            NavigationStack { PlacesView() }.tabBarSpace(!keyboardUp).tag(4)
        }
        .overlay {
            if agentEnabled && (agentOpened || tab == Self.agentTag) {
                let on = tab == Self.agentTag
                NavigationStack { AgentView() }.tabBarSpace(!keyboardUp)
                    .opacity(on ? 1 : 0)
                    .allowsHitTesting(on)
                    .accessibilityHidden(!on)
                    .onAppear { agentOpened = true }
            }
        }
        .onChange(of: tab) { old, _ in if old != Self.agentTag { lastTab = old } }
        .onChange(of: agentEnabled, initial: true) { _, on in
            if !on {
                agentOpened = false
                if tab == Self.agentTag { tab = lastTab }
            }
        }
        .overlay(alignment: .bottom) {
            // the floating bar would otherwise ride up on top of the keyboard
            if !keyboardUp { ToonTabBar(selection: $tab, showAgent: agentEnabled) }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        #endif
        .onOpenURL { url in
            guard url.scheme == "hht", let r = url.host().flatMap(AppRoute.init(rawValue:)) else { return }
            tab = r == .stats ? 3 : 0
            // before onboarding there's no location permission yet: just open, don't save a stamp behind the sheet
            if r == .stamp && !onboarded { return }
            if r == .stamp { todayStack += 1 }
            if r != .today { model.route = r }
        }
        .tint(Toon.accentDeep)
        .fontDesign(.rounded)
        .preferredColorScheme(.light)
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                          set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
                .interactiveDismissDisabled()
        }
    }
}

extension View {
    /// Hides the system tab bar and reserves room at the bottom of every screen in the tab
    /// (including pushed ones) so content can scroll clear of the floating ToonTabBar.
    func tabBarSpace(_ visible: Bool) -> some View {
        toolbar(.hidden, for: .tabBar)
            .contentMargins(.bottom, visible ? ToonTabBar.reservedHeight : 0, for: .scrollContent)
            .environment(\.tabBarSpace, visible ? ToonTabBar.reservedHeight : 0)
    }
}

private struct TabBarSpaceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// Height covered by the floating tab bar, for non-scrolling screens that pin content to the bottom.
    var tabBarSpace: CGFloat {
        get { self[TabBarSpaceKey.self] }
        set { self[TabBarSpaceKey.self] = newValue }
    }
}

/// Floating sticker tab bar: the selected tab grows into a labelled pill.
struct ToonTabBar: View {
    @Binding var selection: Int
    var showAgent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Bar height + shadow + breathing room above it.
    static let reservedHeight: CGFloat = 80

    private var items: [(tag: Int, title: String, symbol: String)] { Self.allItems.filter { showAgent || $0.tag != 5 } }

    private static let allItems: [(tag: Int, title: String, symbol: String)] = [
        (0, "Today", "calendar.day.timeline.left"),
        (5, "Agent", "bubble.left.and.text.bubble.right"),
        (1, "Timeline", "list.bullet.below.rectangle"),
        (2, "Map", "map"),
        (3, "Stats", "chart.bar.xaxis"),
        (4, "Places", "mappin.and.ellipse"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                let on = selection == item.tag
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3)) { selection = item.tag }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: .bold))
                        // five tabs have to fit across the screen: at accessibility text sizes the bar shows icons
                        // only (like the system tab bar), and long-pressing a tab shows its name in the large content viewer
                        if on && !typeSize.isAccessibilitySize { Text(item.title).font(.toon(14, .black)).lineLimit(1).fixedSize() }
                    }
                    .foregroundStyle(Toon.ink)
                    .padding(.horizontal, on ? 14 : 0)
                    .frame(minWidth: 46, minHeight: 46)
                    .background {
                        if on {
                            Capsule().fill(Toon.accent).overlay(Capsule().strokeBorder(Toon.ink, lineWidth: Toon.line))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("tab-\(item.title)")
                .accessibilityShowsLargeContentViewer { Label(item.title, systemImage: item.symbol) }
                if item.tag != items.last?.tag { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 64)
        .toonCard(radius: 32, shadow: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }
}

/// Wraps an ID so it can drive `.sheet(item:)`.
struct IDBox: Identifiable, Hashable { let id: String }

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    var done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Mascot(size: 110)
                        Text("Your private\ntravel diary")
                            .font(.toon(34, .bold)).multilineTextAlignment(.center)
                        Text("TripLibre records where you go, reconstructs your day into visits and trips (like a household travel survey for one), and lets you correct it in a couple of taps.")
                            .font(.toon(15, .bold)).foregroundStyle(Toon.muted).multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    feature("lock.shield", Toon.sun, "Everything stays on this iPhone in a local SQLite database. No account, no server.", -1.5)
                    feature("location", Toon.sky, "Location “Always” lets it log trips in the background. It uses GPS only while you're moving.", 1)
                    feature("figure.walk.motion", Toon.lime, "Motion & Fitness activity helps tell walking, cycling and vehicles apart.", -1)
                    feature("square.and.arrow.up", Toon.bubblegum, "Export CSV / JSON / GeoJSON / SQLite any time from Settings — for R, Python, QGIS.", 1.5)
                    Text("After allowing “While Using”, iOS will later ask to upgrade to “Always”. Choose “Change to Always Allow”.")
                        .font(.toon(12, .bold)).foregroundStyle(Toon.muted).multilineTextAlignment(.center)
                    Button {
                        model.collector.start()
                        model.motion.requestPermission { model.collector.startMotionUpdatesIfAuthorized() }
                        done()
                    } label: {
                        Text("Allow location & start").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToonButtonStyle(fill: Toon.accent, height: 56, fontSize: 19, shadow: 5))
                    Button("Not now") { done() }
                        .font(.toon(15)).foregroundStyle(Toon.ink).underline()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Toon.ink)
                .padding(20)
            }
            .background(ToonBackground())
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ text: String, _ tilt: Double) -> some View {
        HStack(spacing: 12) {
            ToonChip(symbol: symbol, color: color, size: 44)
            Text(text).font(.toon(14, .bold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .toonCard(radius: 20)
        .tilt(tilt)
    }
}
