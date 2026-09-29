import Combine
import Foundation

enum PanelPlacement: String, Codable, CaseIterable {
    case nearMouse, screenCenter
}

enum InsertMethod: String, Codable, CaseIterable {
    /// 클립보드 백업 → 이모지 복사 → ⌘V → 복원
    case paste
    /// CGEvent 유니코드 문자열로 직접 타이핑
    case typeUnicode
}

/// 앱 설정. UserDefaults 위의 ObservableObject.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let autoPopupEnabled = "autoPopupEnabled"
        static let minWordLength = "minWordLength"
        static let matchKeywordPrefix = "matchKeywordPrefix"
        static let enterSelects = "enterSelects"
        static let englishTrigger = "englishTrigger"
        static let maxSuggestions = "maxSuggestions"
        static let insertMethod = "insertMethod"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let hotKey = "hotKey"
        static let panelPlacement = "panelPlacement"
        static let didPromptPermission = "didPromptPermission"
    }

    @Published var autoPopupEnabled: Bool { didSet { Self.defaults.set(autoPopupEnabled, forKey: Key.autoPopupEnabled) } }
    @Published var minWordLength: Int { didSet { Self.defaults.set(minWordLength, forKey: Key.minWordLength) } }
    @Published var matchKeywordPrefix: Bool { didSet { Self.defaults.set(matchKeywordPrefix, forKey: Key.matchKeywordPrefix) } }
    @Published var enterSelects: Bool { didSet { Self.defaults.set(enterSelects, forKey: Key.enterSelects) } }
    @Published var englishTrigger: Bool { didSet { Self.defaults.set(englishTrigger, forKey: Key.englishTrigger) } }
    @Published var maxSuggestions: Int { didSet { Self.defaults.set(maxSuggestions, forKey: Key.maxSuggestions) } }
    @Published var insertMethod: InsertMethod { didSet { Self.defaults.set(insertMethod.rawValue, forKey: Key.insertMethod) } }
    @Published var excludedBundleIDs: [String] { didSet { Self.defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) } }
    @Published var hotKey: KeyCombo {
        didSet { Self.defaults.set(try? JSONEncoder().encode(hotKey), forKey: Key.hotKey) }
    }
    @Published var panelPlacement: PanelPlacement { didSet { Self.defaults.set(panelPlacement.rawValue, forKey: Key.panelPlacement) } }

    var didPromptPermission: Bool {
        get { Self.defaults.bool(forKey: Key.didPromptPermission) }
        set { Self.defaults.set(newValue, forKey: Key.didPromptPermission) }
    }

    private init() {
        let d = Self.defaults
        d.register(defaults: [
            Key.autoPopupEnabled: true,
            Key.minWordLength: 2,
            Key.matchKeywordPrefix: true,
            Key.enterSelects: false,
            Key.englishTrigger: false,
            Key.maxSuggestions: 8,
            Key.insertMethod: InsertMethod.paste.rawValue,
            Key.panelPlacement: PanelPlacement.nearMouse.rawValue,
        ])
        autoPopupEnabled = d.bool(forKey: Key.autoPopupEnabled)
        minWordLength = max(1, min(3, d.integer(forKey: Key.minWordLength)))
        matchKeywordPrefix = d.bool(forKey: Key.matchKeywordPrefix)
        enterSelects = d.bool(forKey: Key.enterSelects)
        englishTrigger = d.bool(forKey: Key.englishTrigger)
        maxSuggestions = max(3, min(12, d.integer(forKey: Key.maxSuggestions)))
        insertMethod = InsertMethod(rawValue: d.string(forKey: Key.insertMethod) ?? "") ?? .paste
        excludedBundleIDs = d.stringArray(forKey: Key.excludedBundleIDs) ?? []
        hotKey = d.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .default
        panelPlacement = PanelPlacement(rawValue: d.string(forKey: Key.panelPlacement) ?? "") ?? .nearMouse
    }

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func toggleExcluded(bundleID: String) {
        if let i = excludedBundleIDs.firstIndex(of: bundleID) {
            excludedBundleIDs.remove(at: i)
        } else {
            excludedBundleIDs.append(bundleID)
        }
    }
}
