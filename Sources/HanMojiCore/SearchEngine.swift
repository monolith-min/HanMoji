import Foundation

public struct SearchOptions {
    public var limit: Int = 48
    /// 이 등급보다 나쁜 매칭은 제외
    public var maxTier: HangulPattern.MatchTier = .substring
    public init(limit: Int = 48, maxTier: HangulPattern.MatchTier = .substring) {
        self.limit = limit
        self.maxTier = maxTier
    }
}

/// 인메모리 검색 인덱스 + 매칭/정렬. 앱 시작 시 한 번 만들어 재사용한다.
public final class SearchEngine {
    public let database: EmojiDatabase
    public var entries: [EmojiEntry] { database.entries }

    private struct Token {
        let units: [UInt32]
        let entry: Int32
        /// 0 = 키워드/이름 전체, 1 = 키워드 안의 부분 단어 (단어 접두 등급으로 제한)
        let weight: UInt8
    }

    private let tokens: [Token]
    private let indexByEmoji: [String: Int]
    public private(set) var tokenCount: Int = 0

    public init(database: EmojiDatabase) {
        self.database = database
        var tokens = [Token]()
        var byEmoji = [String: Int]()
        tokens.reserveCapacity(database.entries.count * 12)

        for (i, entry) in database.entries.enumerated() {
            byEmoji[entry.emoji] = i
            var seen = Set<[UInt32]>()
            func add(_ text: String, weight: UInt8) {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                let units = HangulPattern.encode(t)
                if seen.insert(units).inserted {
                    tokens.append(Token(units: units, entry: Int32(i), weight: weight))
                }
            }
            func addWithWords(_ text: String) {
                add(text, weight: 0)
                let words = SearchEngine.splitWords(text)
                if words.count > 1 { for w in words { add(w, weight: 1) } }
            }
            for k in entry.koreanKeywords { addWithWords(k) }
            if let n = entry.koreanName { addWithWords(n) }
            for k in entry.englishKeywords { addWithWords(k) }
            addWithWords(entry.englishName)
        }
        self.tokens = tokens
        self.indexByEmoji = byEmoji
        self.tokenCount = tokens.count
    }

    private static let wordSeparators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",:;/()[]·"))

    static func splitWords(_ text: String) -> [String] {
        text.components(separatedBy: wordSeparators).filter { !$0.isEmpty }
    }

    public func entry(for emoji: String) -> EmojiEntry? {
        indexByEmoji[emoji].map { database.entries[$0] }
    }

    /// 검색어가 비어 있으면 최근 사용 → 없으면 DB 앞부분.
    public func defaultResults(recents: [String], limit: Int) -> [EmojiEntry] {
        var out = [EmojiEntry]()
        var used = Set<String>()
        for r in recents {
            if let e = entry(for: r), used.insert(r).inserted { out.append(e) }
            if out.count >= limit { return out }
        }
        if out.isEmpty {
            for e in database.entries.prefix(limit) { out.append(e) }
        }
        return out
    }

    /// 패널 검색. 정확 > 접두 > 단어 접두 > 키워드가 검색어의 접두 > 부분 일치 순, 동급이면 최근 사용 → DB 순서.
    public func search(_ query: String, recents: [String] = [], options: SearchOptions = SearchOptions()) -> [EmojiEntry] {
        let pattern = HangulPattern.compile(query)
        guard !pattern.isEmpty else { return defaultResults(recents: recents, limit: options.limit) }
        return search(pattern: pattern, recents: recents, options: options)
    }

    /// 자동 팝업용 후보. 입력 중인 단어에 대해 좁은 매칭만 허용한다.
    /// - minLength: 최소 글자 수 (음절/자모 포함)
    /// - allowKeywordPrefix: "사랑해" → "사랑" 처럼 키워드가 단어의 접두인 경우 허용
    public func suggestions(forTypedWord word: String, recents: [String] = [],
                            minLength: Int = 2, allowKeywordPrefix: Bool = true, limit: Int = 8) -> [EmojiEntry] {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return [] }
        // 모음만 나열된 입력(ㅗㅗ)은 오타일 뿐이라 잡음 → 제외. 자음만(ㅋㅋ, ㅎㅎ)은 키워드가 있으므로 허용.
        if trimmed.allSatisfy(Hangul.isVowelJamo) { return [] }
        let pattern = HangulPattern.compile(trimmed)
        guard !pattern.isEmpty else { return [] }
        let options = SearchOptions(limit: limit, maxTier: allowKeywordPrefix ? .keywordIsPrefix : .wordPrefix)
        return search(pattern: pattern, recents: recents, options: options)
    }

    private func search(pattern: HangulPattern, recents: [String], options: SearchOptions) -> [EmojiEntry] {
        let entries = database.entries
        let maxScore = UInt8(options.maxTier.rawValue)
        var best = [UInt8](repeating: .max, count: entries.count)
        var hitCount = 0

        for t in tokens {
            guard var tier = pattern.match(in: t.units) else { continue }
            // 키워드 안의 부분 단어("큰 기쁨"의 "기쁨")는 단어 접두 등급 이상으로 올라가지 않는다.
            if t.weight == 1, tier < .wordPrefix { tier = .wordPrefix }
            let score = UInt8(tier.rawValue)
            guard score <= maxScore else { continue }
            let idx = Int(t.entry)
            if best[idx] == .max { hitCount += 1 }
            if score < best[idx] { best[idx] = score }
        }
        guard hitCount > 0 else { return [] }

        var recentRank = [String: Int]()
        for (i, r) in recents.enumerated() where recentRank[r] == nil { recentRank[r] = i }

        struct Hit { let index: Int; let score: UInt8; let recent: Int }
        var hits = [Hit]()
        hits.reserveCapacity(hitCount)
        for i in 0..<best.count where best[i] != .max {
            hits.append(Hit(index: i, score: best[i], recent: recentRank[entries[i].emoji] ?? Int.max))
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            if a.recent != b.recent { return a.recent < b.recent }
            return a.index < b.index
        }
        return hits.prefix(options.limit).map { entries[$0.index] }
    }
}
