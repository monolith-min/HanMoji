import Foundation

/// 두벌식 자판: 라틴 문자 → 자모.
public enum Dubeolsik {
    private static let base: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ", "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ", "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
    ]
    private static let shifted: [Character: Character] = [
        "q": "ㅃ", "w": "ㅉ", "e": "ㄸ", "r": "ㄲ", "t": "ㅆ", "o": "ㅒ", "p": "ㅖ",
    ]

    /// 두벌식에서 해당 키가 만드는 자모. 자모 키가 아니면 nil.
    public static func jamo(forLatin c: Character, shift: Bool) -> Character? {
        let lower = Character(String(c).lowercased())
        if shift, let s = shifted[lower] { return s }
        return base[lower]
    }
}

/// 두벌식 한글 오토마타.
///
/// 키 입력(자모)을 받아 현재 단어를 조합한다. macOS 한글 IME의 동작을 흉내내되
/// 우리가 필요한 건 (1) 화면에 보이는 문자열, (2) 그 문자열을 지우기 위해 보내야 할 Backspace 수다.
///
/// macOS 한글 IME의 Backspace 동작 (TextEdit에서 실측, macOS 27):
/// - 확정된 음절은 한 글자에 1회
/// - 조합 중인 음절은 자모 단위. 단, 초성 쌍자음(ㄲㄸㅃㅆㅉ)은 홑자음을 거쳐 2회 (짜 → ㅉ → ㅈ → "")
/// - 종성은 쌍자음이라도 1회 (있 → 이), 복합종성은 첫 자음만 남음 (닭 → 달)
/// - 두 키로 만든 복합모음은 2회 (왜 → 오 → ㅇ), Shift로 친 ㅒ/ㅖ는 1회
/// - 종성이 다음 음절 초성으로 넘어간 뒤(도깨비불) 이전 음절은 확정됨 (가기 → 가ㄱ → 가)
///   넘어간 자음이 쌍자음이면 역시 2회 (이써 → 이ㅆ → 이ㅅ → 이)
public struct HangulComposer: Equatable {
    public struct Syllable: Equatable {
        public var cho: Int?
        public var jung: Int?
        /// 0 = 없음
        public var jong: Int = 0
        /// 이 음절을 만드는 데 들어간 자모 키 수 (Backspace 계산용)
        public var keystrokes: Int = 0

        public var text: String {
            if let cho, let jung { return String(Hangul.compose(cho: cho, jung: jung, jong: jong)) }
            if let cho { return String(Hangul.choseong[cho]) }
            if let jung { return String(Hangul.jungseong[jung]) }
            return ""
        }
    }

    /// 확정된 음절들 (각 1글자)
    public private(set) var committed: [String] = []
    /// 조합 중인 음절
    public private(set) var composing: Syllable?

    public init() {}

    public var text: String { committed.joined() + (composing?.text ?? "") }
    public var isEmpty: Bool { committed.isEmpty && composing == nil }
    /// 화면에 보이는 글자 수
    public var characterCount: Int { committed.count + (composing == nil ? 0 : 1) }
    /// 현재 텍스트를 모두 지우기 위해 대상 앱에 보내야 하는 Backspace 수
    public var deletionKeystrokes: Int { committed.count + (composing?.keystrokes ?? 0) }

    public mutating func reset() {
        committed.removeAll()
        composing = nil
    }

    /// 자모 한 개 입력.
    public mutating func input(_ jamo: Character) {
        if let cho = Hangul.choseongIndex(of: jamo) {
            inputConsonant(jamo, cho: cho)
        } else if let jung = Hangul.jungseongIndex(of: jamo) {
            inputVowel(jamo, jung: jung)
        }
        // 종성 전용 복합자음(ㄳ 등)은 두벌식 키에 없으므로 무시
    }

    /// 문자열의 자모를 차례로 입력 (테스트/편의용)
    public mutating func input(jamoSequence: String) {
        for c in jamoSequence { input(c) }
    }

    private mutating func commitComposing() {
        if let c = composing, !c.text.isEmpty { committed.append(c.text) }
        composing = nil
    }

    /// 초성으로 놓일 때 IME가 되돌리는 데 드는 단계 수 (쌍자음 2, 홑자음 1)
    private static func choSteps(_ cho: Int) -> Int {
        Hangul.isDoubleConsonant(cho: cho) ? 2 : 1
    }

    private mutating func inputConsonant(_ jamo: Character, cho: Int) {
        guard var cur = composing else {
            composing = Syllable(cho: cho, keystrokes: Self.choSteps(cho))
            return
        }
        if cur.cho != nil, cur.jung != nil {
            if cur.jong == 0 {
                if let jong = Hangul.jongseongIndex(of: jamo) {
                    cur.jong = jong
                    cur.keystrokes += 1
                    composing = cur
                    return
                }
            } else if let cluster = Hangul.combineJong(cur.jong, with: jamo) {
                cur.jong = cluster
                cur.keystrokes += 1
                composing = cur
                return
            }
        }
        // 초성만 있거나, 모음만 있거나, 종성으로 붙일 수 없는 경우 → 새 음절
        commitComposing()
        composing = Syllable(cho: cho, keystrokes: Self.choSteps(cho))
    }

    private mutating func inputVowel(_ jamo: Character, jung: Int) {
        guard var cur = composing else {
            composing = Syllable(jung: jung, keystrokes: 1)
            return
        }
        if cur.jung == nil {
            // 초성만 있는 상태
            cur.jung = jung
            cur.keystrokes += 1
            composing = cur
            return
        }
        if cur.jong == 0 {
            if let compound = Hangul.combineJung(cur.jung!, with: jamo) {
                cur.jung = compound
                cur.keystrokes += 1
                composing = cur
                return
            }
            commitComposing()
            composing = Syllable(jung: jung, keystrokes: 1)
            return
        }
        // 도깨비불: 종성(또는 복합 종성의 둘째 자음)이 다음 음절 초성으로 이동
        guard let (remain, moved) = Hangul.splitJong(cur.jong) else {
            commitComposing()
            composing = Syllable(jung: jung, keystrokes: 1)
            return
        }
        cur.jong = remain
        cur.keystrokes -= 1
        committed.append(cur.text)
        composing = Syllable(cho: moved, jung: jung, keystrokes: Self.choSteps(moved) + 1)
    }

    /// Backspace 한 번. 지울 것이 없으면 false.
    @discardableResult
    public mutating func backspace() -> Bool {
        if var cur = composing {
            if cur.jong != 0 {
                cur.jong = Hangul.splitJong(cur.jong)?.remain ?? 0
            } else if let jung = cur.jung {
                if let (first, _) = Hangul.splitJung(jung) {
                    cur.jung = first
                } else if cur.cho != nil {
                    cur.jung = nil
                } else {
                    composing = nil
                    return true
                }
            } else if let cho = cur.cho, let single = Hangul.singleConsonant(forDoubleCho: cho) {
                // 초성 쌍자음만 남은 상태: 홑자음으로 (ㅃ → ㅂ)
                cur.cho = single
            } else {
                // 홑자음 초성만
                composing = nil
                return true
            }
            cur.keystrokes = max(0, cur.keystrokes - 1)
            composing = cur
            return true
        }
        if !committed.isEmpty {
            committed.removeLast()
            return true
        }
        return false
    }
}
