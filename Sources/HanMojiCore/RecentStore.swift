import Foundation

/// 최근 사용 이모지. MRU 순서, UserDefaults에 저장.
public final class RecentStore {
    private let defaults: UserDefaults
    private let key: String
    public let limit: Int
    public private(set) var items: [String]

    public init(defaults: UserDefaults = .standard, key: String = "recentEmojis", limit: Int = 30) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
        self.items = defaults.stringArray(forKey: key) ?? []
    }

    public func record(_ emoji: String) {
        items.removeAll { $0 == emoji }
        items.insert(emoji, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        defaults.set(items, forKey: key)
    }

    public func clear() {
        items.removeAll()
        defaults.removeObject(forKey: key)
    }
}
