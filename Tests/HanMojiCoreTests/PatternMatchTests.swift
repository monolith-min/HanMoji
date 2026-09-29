import XCTest
@testable import HanMojiCore

final class PatternMatchTests: XCTestCase {
    private func tier(_ query: String, _ keyword: String) -> HangulPattern.MatchTier? {
        HangulPattern.compile(query).match(in: HangulPattern.encode(keyword))
    }

    func testExactAndPrefix() {
        XCTAssertEqual(tier("기쁨", "기쁨"), .exact)
        XCTAssertEqual(tier("기쁨", "기쁨의 눈물"), .prefix)
        XCTAssertEqual(tier("쁨", "기쁨"), .substring)
        XCTAssertNil(tier("슬픔", "기쁨"))
    }

    func testInitialConsonantSearch() {
        XCTAssertEqual(tier("ㄱㅃ", "기쁨"), .exact)
        XCTAssertEqual(tier("ㄱㅃ", "기쁨의 눈물"), .prefix)
        XCTAssertEqual(tier("ㅇㄱ", "웃는 얼굴"), .wordPrefix)
        XCTAssertNil(tier("ㄴㅃ", "기쁨"))
        // 낱자음 + 완성 음절 혼합
        XCTAssertEqual(tier("ㄱ쁨", "기쁨"), .exact)
        XCTAssertEqual(tier("기ㅃ", "기쁨"), .exact)
    }

    func testComposingLastSyllableWildcardJong() {
        // 마지막 글자에 종성이 없으면 종성은 와일드카드
        XCTAssertEqual(tier("기쁘", "기쁨"), .exact)
        XCTAssertEqual(tier("우", "웃음"), .prefix)
        // 마지막 글자가 아니면 종성 없음도 정확히 비교
        XCTAssertNil(tier("사과", "삵과"))
        XCTAssertEqual(tier("사과", "사과"), .exact)
        // 종성이 있으면 정확히 비교
        XCTAssertNil(tier("기쁨", "기쁘다"))
    }

    func testVowelOnlyElementMatchesJung() {
        XCTAssertEqual(tier("ㅜ", "웃음"), .prefix)
        XCTAssertNil(tier("ㅏ", "웃음"))
    }

    func testWordPrefix() {
        XCTAssertEqual(tier("얼굴", "웃는 얼굴"), .wordPrefix)
        XCTAssertEqual(tier("얼", "웃는 얼굴"), .wordPrefix)
    }

    func testKeywordIsPrefixOfQuery() {
        XCTAssertEqual(tier("사랑해", "사랑"), .keywordIsPrefix)
        XCTAssertEqual(tier("기쁨이", "기쁨"), .keywordIsPrefix)
        // 1글자 키워드는 잡음이 커서 제외
        XCTAssertNil(tier("손가락", "손"))
        XCTAssertNil(tier("사랑해", "사람"))
    }

    func testEnglishCaseInsensitive() {
        XCTAssertEqual(tier("smile", "smile"), .exact)
        XCTAssertEqual(tier("SMIL", "smiling face"), .prefix)
        XCTAssertEqual(tier("face", "smiling face"), .wordPrefix)
        XCTAssertEqual(tier("ace", "smiling face"), .substring)
        XCTAssertNil(tier("smile", "grin"))
    }

    func testMixedScripts() {
        XCTAssertEqual(tier("ok", "OK 사인"), .prefix)
        XCTAssertEqual(tier("100", "100점"), .prefix)
    }

    func testEmptyAndWhitespaceQuery() {
        XCTAssertTrue(HangulPattern.compile("").isEmpty)
        XCTAssertTrue(HangulPattern.compile("   ").isEmpty)
        XCTAssertEqual(HangulPattern.compile(" 기쁨 ").count, 2)
    }

    func testHangulCount() {
        XCTAssertEqual(HangulPattern.compile("기쁨").hangulCount, 2)
        XCTAssertEqual(HangulPattern.compile("기ㅃ").hangulCount, 2)
        XCTAssertEqual(HangulPattern.compile("ok").hangulCount, 0)
    }
}
