import XCTest
@testable import HanMojiCore

final class HangulComposerTests: XCTestCase {
    private func compose(_ jamo: String) -> HangulComposer {
        var c = HangulComposer()
        c.input(jamoSequence: jamo)
        return c
    }

    func testBasicSyllables() {
        XCTAssertEqual(compose("ㄱㅣㅃㅡㅁ").text, "기쁨")
        XCTAssertEqual(compose("ㅇㅜㅅㅇㅡㅁ").text, "웃음")
        XCTAssertEqual(compose("ㅎㅏㅌㅡ").text, "하트")
    }

    func testDoubleConsonantCannotBeJong() {
        // ㅃ는 종성이 될 수 없으므로 새 음절 시작
        XCTAssertEqual(compose("ㄱㅣㅃ").text, "기ㅃ")
        XCTAssertEqual(compose("ㄱㅣㅃㅡ").text, "기쁘")
    }

    func testJongCluster() {
        XCTAssertEqual(compose("ㄷㅏㄹㄱ").text, "닭")
        XCTAssertEqual(compose("ㅇㅣㅆ").text, "있")
        XCTAssertEqual(compose("ㅇㅏㄴㅈ").text, "앉")
    }

    func testCompoundVowel() {
        XCTAssertEqual(compose("ㅇㅗㅏ").text, "와")
        XCTAssertEqual(compose("ㄱㅡㅣ").text, "긔")
        XCTAssertEqual(compose("ㅇㅜㅓ").text, "워")
        // 결합 불가 모음은 새 음절(모음 단독)
        XCTAssertEqual(compose("ㄱㅏㅓ").text, "가ㅓ")
    }

    func testDokkaebibul_JongMovesToNextCho() {
        XCTAssertEqual(compose("ㄱㅏㄱㅣ").text, "가기")
        XCTAssertEqual(compose("ㄱㅣㅃㅡㅁㅣ").text, "기쁘미")
        XCTAssertEqual(compose("ㅇㅣㅆㅓ").text, "이써")
        // 복합 종성은 둘째 자음만 이동
        XCTAssertEqual(compose("ㄷㅏㄹㄱㅏ").text, "달가")
        XCTAssertEqual(compose("ㅇㅏㄴㅈㅏ").text, "안자")
    }

    func testStandaloneJamo() {
        XCTAssertEqual(compose("ㄱㄷ").text, "ㄱㄷ")
        XCTAssertEqual(compose("ㅏ").text, "ㅏ")
        XCTAssertEqual(compose("ㅏㄱ").text, "ㅏㄱ")
        XCTAssertEqual(compose("ㅋㅋㅋ").text, "ㅋㅋㅋ")
    }

    func testBackspaceRemovesJamoWhileComposing() {
        var c = compose("ㄱㅣㅃㅡㅁ")
        XCTAssertEqual(c.text, "기쁨")
        c.backspace(); XCTAssertEqual(c.text, "기쁘")
        c.backspace(); XCTAssertEqual(c.text, "기ㅃ")
        c.backspace(); XCTAssertEqual(c.text, "기ㅂ") // 쌍자음 초성은 홑자음을 거친다
        c.backspace(); XCTAssertEqual(c.text, "기")
        // 조합 중 음절이 사라진 뒤에는 확정 음절이 한 글자씩 지워진다
        c.backspace(); XCTAssertEqual(c.text, "")
        XCTAssertTrue(c.isEmpty)
        XCTAssertFalse(c.backspace())
    }

    func testBackspaceOnClusterAndCompound() {
        var c = compose("ㄷㅏㄹㄱ")
        c.backspace(); XCTAssertEqual(c.text, "달")
        c.backspace(); XCTAssertEqual(c.text, "다")
        var d = compose("ㅇㅗㅏ")
        d.backspace(); XCTAssertEqual(d.text, "오")
        d.backspace(); XCTAssertEqual(d.text, "ㅇ")
        d.backspace(); XCTAssertEqual(d.text, "")
    }

    func testBackspaceAfterDokkaebibulDoesNotRestorePreviousSyllable() {
        // macOS IME: 이전 음절은 확정되므로 "가기" → "가ㄱ"
        var c = compose("ㄱㅏㄱㅣ")
        c.backspace(); XCTAssertEqual(c.text, "가ㄱ")
        c.backspace(); XCTAssertEqual(c.text, "가")
    }

    /// TextEdit(macOS 27)에서 Backspace를 한 번씩 보내 실측한 값과 같아야 한다.
    func testDeletionKeystrokesMatchMeasuredIMEBehavior() {
        XCTAssertEqual(compose("ㄱㅣㅃㅡㅁ").deletionKeystrokes, 1 + 4)   // 기쁨: 기(확정) + 쁨(ㅃ=2, ㅡ, ㅁ)
        XCTAssertEqual(compose("ㄱㅏㄱㅣ").deletionKeystrokes, 1 + 2)     // 가기: 가(확정) + 기(ㄱㅣ)
        XCTAssertEqual(compose("ㄷㅏㄹㄱ").deletionKeystrokes, 4)         // 닭: 달 → 다 → ㄷ → ""
        XCTAssertEqual(compose("ㄷㅏㄹㄱㅏ").deletionKeystrokes, 1 + 2)   // 달가: 달(확정) + 가
        XCTAssertEqual(compose("ㅇㅜㅅㅇㅡㅁ").deletionKeystrokes, 1 + 3) // 웃음: 웃 + 음
        XCTAssertEqual(compose("ㅇㅣㅆ").deletionKeystrokes, 3)           // 있: 종성 ㅆ은 1회
        XCTAssertEqual(compose("ㅉㅏ").deletionKeystrokes, 3)             // 짜: ㅉ → ㅈ → ""
        XCTAssertEqual(compose("ㅃㅏㅇ").deletionKeystrokes, 4)           // 빵: 빠 → ㅃ → ㅂ → ""
        XCTAssertEqual(compose("ㅇㅣㅆㅓ").deletionKeystrokes, 1 + 3)     // 이써: 이(확정) + 써(ㅆ=2, ㅓ)
        XCTAssertEqual(compose("ㄲㅐ").deletionKeystrokes, 3)             // 깨: ㄲ → ㄱ → ""
        XCTAssertEqual(compose("ㅇㅗㅐ").deletionKeystrokes, 3)           // 왜: 오 → ㅇ → ""
        XCTAssertEqual(compose("ㅇㅒ").deletionKeystrokes, 2)             // 얘: Shift 모음은 1회
        XCTAssertEqual(compose("ㅋㅋㅋ").deletionKeystrokes, 2 + 1)
        XCTAssertEqual(HangulComposer().deletionKeystrokes, 0)
    }

    func testBackspaceOnDoubleConsonantGoesThroughSingle() {
        var c = compose("ㅉㅏ")
        c.backspace(); XCTAssertEqual(c.text, "ㅉ")
        c.backspace(); XCTAssertEqual(c.text, "ㅈ")
        c.backspace(); XCTAssertEqual(c.text, "")
        var d = compose("ㅇㅣㅆㅓ")
        d.backspace(); XCTAssertEqual(d.text, "이ㅆ")
        d.backspace(); XCTAssertEqual(d.text, "이ㅅ")
        d.backspace(); XCTAssertEqual(d.text, "이")
        var e = compose("ㅇㅣㅆ")
        e.backspace(); XCTAssertEqual(e.text, "이") // 종성 ㅆ은 한 번에
    }

    func testCharacterCount() {
        XCTAssertEqual(compose("ㄱㅣㅃㅡㅁ").characterCount, 2)
        XCTAssertEqual(compose("ㄱㅣㅃ").characterCount, 2)
        XCTAssertEqual(compose("ㄱ").characterCount, 1)
    }

    func testDubeolsikMapping() {
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "r", shift: false), "ㄱ")
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "r", shift: true), "ㄲ")
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "R", shift: true), "ㄲ")
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "t", shift: true), "ㅆ")
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "o", shift: true), "ㅒ")
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "k", shift: true), "ㅏ") // 시프트에 별도 자모 없음
        XCTAssertEqual(Dubeolsik.jamo(forLatin: "q", shift: false), "ㅂ")
        XCTAssertNil(Dubeolsik.jamo(forLatin: "1", shift: false))
        XCTAssertNil(Dubeolsik.jamo(forLatin: ";", shift: false))
    }

    func testTypingViaDubeolsikKeys() {
        var c = HangulComposer()
        for (ch, shift) in [("r", false), ("l", false), ("q", true), ("m", false), ("a", false)] {
            c.input(Dubeolsik.jamo(forLatin: Character(ch), shift: shift)!)
        }
        XCTAssertEqual(c.text, "기쁨")
    }
}
