import SwiftUI
import Foundation
#if canImport(ObjectiveC)
import ObjectiveC
#endif

/// Languages the app ships translations for (issue #90). Translations live in `App/Localizable.xcstrings`
/// (keys are the English text); `scripts/check_localizations.py` checks every key has every language.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the iPhone's language list (Settings › General › Language & Region).
    case system = ""
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case russian = "ru"
    case arabic = "ar"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    /// Each language's own name for itself, so people can find theirs whatever language the app is showing.
    var nativeName: String {
        switch self {
        case .system: return L("System default")
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    /// The language's name in the app's current language, shown under the native name.
    var localizedName: String? {
        guard self != .system else { return nil }
        return Lang.locale.localizedString(forIdentifier: rawValue)
    }
}

/// The in-app language preference (Settings › Language) and lookups that honour it.
///
/// Choosing a language: points `Bundle.main` string lookups at that `.lproj` straight away (SwiftUI `Text`,
/// `L(...)`), sets the SwiftUI locale and layout direction from the root view, and writes `AppleLanguages` so iOS
/// itself (permission prompts, system sheets) uses it from the next launch.
enum Lang {
    static let defaultsKey = "appLanguage"

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// Localization in use: the chosen language, or iOS's best match among the ones the app ships.
    static var code: String {
        if selected != .system { return selected.rawValue }
        let shipped = Bundle.main.localizations.filter { $0 != "Base" }
        return Bundle.preferredLocalizations(from: shipped, forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    /// Locale for formatting: the app language with the iPhone's region, so currency, units and the first weekday
    /// stay those of where the person lives.
    static var locale: Locale {
        var c = Locale.Components(identifier: code)
        c.region = Locale.current.region
        return Locale(components: c)
    }

    static var isRightToLeft: Bool { Locale.Language(identifier: code).characterDirection == .rightToLeft }
    static var layoutDirection: LayoutDirection { isRightToLeft ? .rightToLeft : .leftToRight }

    /// Call once at launch, before any view loads.
    static func bootstrap() {
        #if canImport(ObjectiveC)
        if !(Bundle.main is LanguageBundle) { object_setClass(Bundle.main, LanguageBundle.self) }
        #endif
        LanguageBundle.load(code)
    }

    /// Switch language. Strings switch at once; iOS-owned text (permission prompts) follows after a relaunch.
    @MainActor static func apply(_ language: AppLanguage) {
        let d = UserDefaults.standard
        if language == .system {
            d.removeObject(forKey: defaultsKey)
            d.removeObject(forKey: "AppleLanguages")
        } else {
            d.set(language.rawValue, forKey: defaultsKey)
            d.set([language.rawValue], forKey: "AppleLanguages")
        }
        LanguageBundle.load(code)
        LanguageController.shared.code = code
    }
}

/// Publishes the language in use so the root view can re-render the whole UI when it changes.
@MainActor
final class LanguageController: ObservableObject {
    static let shared = LanguageController()
    @Published var code = Lang.code
}

/// `Bundle.main` is re-classed to this so every string lookup goes through the chosen `.lproj`.
private final class LanguageBundle: Bundle {
    /// Set at launch and from Settings (main thread); read by every lookup.
    private static var override: Bundle?

    /// Always the resolved language, also for "System default": `Bundle.main` keeps the language it launched with,
    /// so switching back to the system language would otherwise wait for a relaunch.
    static func load(_ code: String) {
        override = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let b = Self.override { return b.localizedString(forKey: key, value: value, table: tableName) }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// Localized text for a key that is the English string (for text that is passed around as `String`).
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Localized format string filled with `args`. Keys use `%@` for text and `%lld` for whole numbers; counts get
/// plural variants in the string catalog.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Lang.locale, arguments: args)
}

extension View {
    /// Applies the app language to a view tree (locale, layout direction) and rebuilds it when the language changes.
    func appLanguage(_ code: String) -> some View {
        environment(\.locale, Lang.locale)
            .environment(\.layoutDirection, Lang.layoutDirection)
            .id(code)
    }
}
