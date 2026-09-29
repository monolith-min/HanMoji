import XCTest
@testable import HanMojiCore

final class HangulTests: XCTestCase {
    func testDecomposeSyllable() {
        XCTAssertEqual(Hangul.decompose("기"), Hangul.Syllable(cho: 0, jung: 20, jong: 0))
        XCTAssertEqual(Hangul.decompose("쁨"), Hangul.Syllable(cho: 8, jung: 18, jong: 16))
        XCTAssertEqual(Hangul.decompose("닭"), Hangul.Syllable(cho: 3, jung: 0, jong: 9))
        XCTAssertNil(Hangul.decompose("a"))
        XCTAssertNil(Hangul.decompose("ㄱ"))
    }

    func testComposeRoundTrip() {
        for ch in "기쁨닭웃음얼굴하트" {
            let s = Hangul.decompose(ch)!
            XCTAssertEqual(Hangul.compose(cho: s.cho, jung: s.jung, jong: s.jong), ch)
        }
    }

    func testInitialConsonants() {
        XCTAssertEqual(Hangul.initialConsonants(of: "기쁨"), "ㄱㅃ")
        XCTAssertEqual(Hangul.initialConsonants(of: "웃는 얼굴"), "ㅇㄴ ㅇㄱ")
        XCTAssertEqual(Hangul.initialConsonants(of: "OK 사인"), "OK ㅅㅇ")
    }

    func testJamoClassification() {
        XCTAssertTrue(Hangul.isConsonantJamo("ㄱ"))
        XCTAssertTrue(Hangul.isConsonantJamo("ㅎ"))
        XCTAssertFalse(Hangul.isConsonantJamo("ㅏ"))
        XCTAssertTrue(Hangul.isVowelJamo("ㅏ"))
        XCTAssertTrue(Hangul.isVowelJamo("ㅣ"))
        XCTAssertFalse(Hangul.isVowelJamo("ㄱ"))
        XCTAssertTrue(Hangul.isHangul("가"))
        XCTAssertFalse(Hangul.isHangul("g"))
    }

    func testChoseongIndexOnlyForValidInitials() {
        XCTAssertEqual(Hangul.choseongIndex(of: "ㄱ"), 0)
        XCTAssertEqual(Hangul.choseongIndex(of: "ㅃ"), 8)
        XCTAssertNil(Hangul.choseongIndex(of: "ㄳ"))
        XCTAssertEqual(Hangul.jongseongIndex(of: "ㄳ"), 3)
        XCTAssertNil(Hangul.jongseongIndex(of: "ㄸ"))
    }

    func testJongClusterRules() {
        let ㄹ = Hangul.jongseongIndex(of: "ㄹ")!
        XCTAssertEqual(Hangul.combineJong(ㄹ, with: "ㄱ"), Hangul.jongseongIndex(of: "ㄺ"))
        XCTAssertNil(Hangul.combineJong(ㄹ, with: "ㄷ"))
        let split = Hangul.splitJong(Hangul.jongseongIndex(of: "ㄺ")!)!
        XCTAssertEqual(split.remain, ㄹ)
        XCTAssertEqual(split.movedCho, Hangul.choseongIndex(of: "ㄱ"))
        let single = Hangul.splitJong(Hangul.jongseongIndex(of: "ㅆ")!)!
        XCTAssertEqual(single.remain, 0)
        XCTAssertEqual(single.movedCho, Hangul.choseongIndex(of: "ㅆ"))
    }

    func testJungCompoundRules() {
        let ㅗ = Hangul.jungseongIndex(of: "ㅗ")!
        XCTAssertEqual(Hangul.combineJung(ㅗ, with: "ㅏ"), Hangul.jungseongIndex(of: "ㅘ"))
        XCTAssertNil(Hangul.combineJung(ㅗ, with: "ㅓ"))
        let split = Hangul.splitJung(Hangul.jungseongIndex(of: "ㅢ")!)!
        XCTAssertEqual(split.first, Hangul.jungseongIndex(of: "ㅡ"))
        XCTAssertEqual(split.second, Hangul.jungseongIndex(of: "ㅣ"))
        XCTAssertNil(Hangul.splitJung(ㅗ))
    }
}
