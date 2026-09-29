import XCTest
@testable import HanMojiCore

final class RankingTests: XCTestCase {
    private func entry(_ e: String, ko: [String], tts: String? = nil, en: [String] = [], name: String = "") -> EmojiEntry {
        EmojiEntry(emoji: e, koreanKeywords: ko, koreanName: tts, englishKeywords: en, englishName: name, group: 0)
    }

    private lazy var engine: SearchEngine = {
        let entries = [
            entry("😊", ko: ["기쁨", "미소"], tts: "미소 짓는 얼굴", en: ["smile", "blush"], name: "smiling face with smiling eyes"),
            entry("😂", ko: ["기쁨의 눈물", "웃음"], tts: "기쁨의 눈물을 흘리는 얼굴", en: ["joy", "tear"], name: "face with tears of joy"),
            entry("🎉", ko: ["파티", "큰 기쁨"], tts: "폭죽", en: ["party", "celebration"], name: "party popper"),
            entry("😢", ko: ["슬픔", "눈물"], tts: "우는 얼굴", en: ["sad", "cry"], name: "crying face"),
            entry("🥰", ko: ["기쁨", "사랑"], tts: "하트 눈 웃는 얼굴", en: ["love", "adore"], name: "smiling face with hearts"),
            entry("❤️", ko: ["사랑", "하트"], tts: "빨간 하트", en: ["heart", "love"], name: "red heart"),
        ]
        return SearchEngine(database: EmojiDatabase(version: "test", groups: ["test"], entries: entries))
    }()

    func testTierOrdering() {
        let r = engine.search("기쁨").map(\.emoji)
        // 정확(😊, 🥰) > 접두(😂) > 단어 접두(🎉). 슬픔은 제외.
        XCTAssertEqual(r, ["😊", "🥰", "😂", "🎉"])
    }

    func testRecentsBreakTiesWithinTier() {
        let r = engine.search("기쁨", recents: ["🥰"]).map(\.emoji)
        XCTAssertEqual(r.prefix(2), ["🥰", "😊"])
        // 최근 사용이라도 등급을 뛰어넘지는 않음
        let r2 = engine.search("기쁨", recents: ["🎉"]).map(\.emoji)
        XCTAssertEqual(r2, ["😊", "🥰", "😂", "🎉"])
    }

    func testInitialConsonantQuery() {
        XCTAssertEqual(engine.search("ㄱㅃ").map(\.emoji), ["😊", "🥰", "😂", "🎉"])
        XCTAssertEqual(engine.search("ㅅㅍ").map(\.emoji), ["😢"])
    }

    func testEnglishQuery() {
        XCTAssertEqual(engine.search("love").map(\.emoji), ["🥰", "❤️"])
        XCTAssertEqual(engine.search("Heart").first?.emoji, "❤️")
    }

    func testEmptyQueryShowsRecentsThenDefaults() {
        XCTAssertEqual(engine.search("", recents: ["❤️", "😂"]).map(\.emoji), ["❤️", "😂"])
        XCTAssertEqual(engine.search("").map(\.emoji), ["😊", "😂", "🎉", "😢", "🥰", "❤️"])
        XCTAssertEqual(engine.search("", recents: ["🦄"]).count, 6) // 모르는 이모지는 무시 → 기본 목록
    }

    func testLimit() {
        XCTAssertEqual(engine.search("기쁨", options: SearchOptions(limit: 2)).count, 2)
    }

    func testSubwordMatchIsCappedAtWordPrefixTier() {
        // "눈물": 😢는 키워드 전체 일치(정확), 😂는 "기쁨의 눈물"의 부분 단어(단어 접두) → 😢 먼저
        XCTAssertEqual(engine.search("눈물").map(\.emoji), ["😢", "😂"])
    }

    func testSuggestionsForTypedWord() {
        XCTAssertEqual(engine.suggestions(forTypedWord: "기쁨").map(\.emoji), ["😊", "🥰", "😂", "🎉"])
        // 조사 붙은 단어: 키워드가 접두
        XCTAssertEqual(engine.suggestions(forTypedWord: "사랑해").map(\.emoji), ["🥰", "❤️"])
        XCTAssertEqual(engine.suggestions(forTypedWord: "사랑해", allowKeywordPrefix: false), [])
        // 최소 글자 수
        XCTAssertEqual(engine.suggestions(forTypedWord: "기", minLength: 2), [])
        XCTAssertFalse(engine.suggestions(forTypedWord: "기", minLength: 1).isEmpty)
        // 조합 중(초성만 있는 둘째 글자)도 후보 제시
        XCTAssertEqual(engine.suggestions(forTypedWord: "기ㅃ").first?.emoji, "😊")
        // 부분 일치는 자동 팝업에서 제외
        XCTAssertEqual(engine.suggestions(forTypedWord: "쁨의"), [])
        // 모음만 나열된 입력은 제외
        XCTAssertEqual(engine.suggestions(forTypedWord: "ㅗㅗ"), [])
    }
}
