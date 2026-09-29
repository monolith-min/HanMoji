import Foundation

/// 이모지 한 개. JSON 키는 번들 크기를 위해 짧게 둔다.
public struct EmojiEntry: Codable, Hashable, Identifiable {
    public var id: String { emoji }

    /// 완전 규격(fully-qualified) 이모지 문자열
    public let emoji: String
    /// CLDR 한국어 키워드
    public let koreanKeywords: [String]
    /// CLDR 한국어 이름(tts)
    public let koreanName: String?
    /// CLDR 영어 키워드
    public let englishKeywords: [String]
    /// emoji-test.txt 영어 이름
    public let englishName: String
    /// EmojiDatabase.groups 인덱스
    public let group: Int

    enum CodingKeys: String, CodingKey {
        case emoji = "e"
        case koreanKeywords = "ko"
        case koreanName = "tts"
        case englishKeywords = "en"
        case englishName = "n"
        case group = "g"
    }

    public init(emoji: String, koreanKeywords: [String], koreanName: String?,
                englishKeywords: [String], englishName: String, group: Int) {
        self.emoji = emoji
        self.koreanKeywords = koreanKeywords
        self.koreanName = koreanName
        self.englishKeywords = englishKeywords
        self.englishName = englishName
        self.group = group
    }
}

public struct EmojiDatabase: Codable {
    public let version: String
    public let groups: [String]
    public let entries: [EmojiEntry]

    public init(version: String, groups: [String], entries: [EmojiEntry]) {
        self.version = version
        self.groups = groups
        self.entries = entries
    }

    public static func load(from url: URL) throws -> EmojiDatabase {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EmojiDatabase.self, from: data)
    }
}
