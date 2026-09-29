import Foundation

/// 한글 음절 ↔ 자모(초성/중성/종성) 변환과 두벌식 조합에 필요한 자모 결합 규칙.
public enum Hangul {
    public static let syllableBase: UInt32 = 0xAC00
    public static let syllableLast: UInt32 = 0xD7A3

    /// 초성 19개. 인덱스가 유니코드 음절 계산에 쓰는 초성 번호.
    public static let choseong: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    /// 중성 21개.
    public static let jungseong: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// 종성 28개. 인덱스 0 = 종성 없음.
    public static let jongseong: [Character?] =
        [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { Optional($0) }

    private static let choIndex: [Character: Int] = index(of: choseong)
    private static let jungIndex: [Character: Int] = index(of: jungseong)
    private static let jongIndex: [Character: Int] = {
        var d = [Character: Int]()
        for (i, c) in jongseong.enumerated() { if let c { d[c] = i } }
        return d
    }()

    private static func index(of list: [Character]) -> [Character: Int] {
        var d = [Character: Int]()
        for (i, c) in list.enumerated() { d[c] = i }
        return d
    }

    public struct Syllable: Equatable {
        public var cho: Int
        public var jung: Int
        /// 0 = 종성 없음
        public var jong: Int
        public init(cho: Int, jung: Int, jong: Int) {
            self.cho = cho; self.jung = jung; self.jong = jong
        }
    }

    // MARK: 판별

    public static func isSyllable(_ s: Unicode.Scalar) -> Bool {
        (syllableBase...syllableLast).contains(s.value)
    }

    /// 호환 자모(ㄱ~ㅣ, U+3131~U+3163)
    public static func isCompatibilityJamo(_ s: Unicode.Scalar) -> Bool {
        (0x3131...0x3163).contains(s.value)
    }

    public static func isConsonantJamo(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x3131...0x314E).contains(s.value)
    }

    public static func isVowelJamo(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x314F...0x3163).contains(s.value)
    }

    public static func isHangul(_ c: Character) -> Bool {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return isSyllable(s) || isCompatibilityJamo(s)
    }

    // MARK: 분해/조합

    public static func decompose(scalar s: Unicode.Scalar) -> Syllable? {
        guard isSyllable(s) else { return nil }
        let i = Int(s.value - syllableBase)
        return Syllable(cho: i / 588, jung: (i % 588) / 28, jong: i % 28)
    }

    public static func decompose(_ c: Character) -> Syllable? {
        guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return nil }
        return decompose(scalar: s)
    }

    public static func compose(cho: Int, jung: Int, jong: Int) -> Character {
        let v = syllableBase + UInt32(cho * 588 + jung * 28 + jong)
        return Character(Unicode.Scalar(v)!)
    }

    public static func choseongIndex(of jamo: Character) -> Int? { choIndex[jamo] }
    public static func jungseongIndex(of jamo: Character) -> Int? { jungIndex[jamo] }
    public static func jongseongIndex(of jamo: Character) -> Int? { jongIndex[jamo] }

    /// "기쁨" → "ㄱㅃ". 한글이 아닌 문자는 그대로 둔다.
    public static func initialConsonants(of text: String) -> String {
        var out = ""
        for c in text {
            if let syl = decompose(c) { out.append(choseong[syl.cho]) } else { out.append(c) }
        }
        return out
    }

    // MARK: 쌍자음

    private static let doubleToSingle: [Character: Character] = ["ㄲ": "ㄱ", "ㄸ": "ㄷ", "ㅃ": "ㅂ", "ㅆ": "ㅅ", "ㅉ": "ㅈ"]

    /// 초성 인덱스가 쌍자음(ㄲㄸㅃㅆㅉ)인지
    public static func isDoubleConsonant(cho: Int) -> Bool {
        doubleToSingle[choseong[cho]] != nil
    }

    /// 쌍자음 초성 → 홑자음 초성 인덱스 (ㅃ → ㅂ). macOS IME는 쌍자음 초성을 Backspace로 홑자음까지 되돌린다.
    public static func singleConsonant(forDoubleCho cho: Int) -> Int? {
        guard let single = doubleToSingle[choseong[cho]] else { return nil }
        return choIndex[single]
    }

    // MARK: 두벌식 결합 규칙

    /// 종성 복합자음: (첫 자음, 둘째 자음) → 복합 종성 인덱스
    private static let jongClusters: [(Character, Character, Character)] = [
        ("ㄱ", "ㅅ", "ㄳ"), ("ㄴ", "ㅈ", "ㄵ"), ("ㄴ", "ㅎ", "ㄶ"),
        ("ㄹ", "ㄱ", "ㄺ"), ("ㄹ", "ㅁ", "ㄻ"), ("ㄹ", "ㅂ", "ㄼ"), ("ㄹ", "ㅅ", "ㄽ"),
        ("ㄹ", "ㅌ", "ㄾ"), ("ㄹ", "ㅍ", "ㄿ"), ("ㄹ", "ㅎ", "ㅀ"), ("ㅂ", "ㅅ", "ㅄ"),
    ]
    private static let jungCompounds: [(Character, Character, Character)] = [
        ("ㅗ", "ㅏ", "ㅘ"), ("ㅗ", "ㅐ", "ㅙ"), ("ㅗ", "ㅣ", "ㅚ"),
        ("ㅜ", "ㅓ", "ㅝ"), ("ㅜ", "ㅔ", "ㅞ"), ("ㅜ", "ㅣ", "ㅟ"), ("ㅡ", "ㅣ", "ㅢ"),
    ]

    /// 현재 종성(인덱스)에 자음을 덧붙여 복합 종성이 되면 그 인덱스를 반환.
    public static func combineJong(_ jong: Int, with consonant: Character) -> Int? {
        guard jong > 0, let first = jongseong[jong] else { return nil }
        for (a, b, r) in jongClusters where a == first && b == consonant { return jongIndex[r] }
        return nil
    }

    /// 종성을 분리: (남는 종성 인덱스, 다음 음절 초성으로 넘어갈 자음의 초성 인덱스).
    /// 홑자음이면 남는 종성은 0.
    public static func splitJong(_ jong: Int) -> (remain: Int, movedCho: Int)? {
        guard jong > 0, let ch = jongseong[jong] else { return nil }
        for (a, b, r) in jongClusters where r == ch {
            guard let remain = jongIndex[a], let moved = choIndex[b] else { return nil }
            return (remain, moved)
        }
        guard let moved = choIndex[ch] else { return nil }
        return (0, moved)
    }

    public static func combineJung(_ jung: Int, with vowel: Character) -> Int? {
        let first = jungseong[jung]
        for (a, b, r) in jungCompounds where a == first && b == vowel { return jungIndex[r] }
        return nil
    }

    /// 복합 모음이면 (첫 모음 인덱스, 둘째 모음 인덱스)
    public static func splitJung(_ jung: Int) -> (first: Int, second: Int)? {
        let ch = jungseong[jung]
        for (a, b, r) in jungCompounds where r == ch {
            guard let f = jungIndex[a], let s = jungIndex[b] else { return nil }
            return (f, s)
        }
        return nil
    }
}
