import Foundation

/// 검색어를 "부분 음절 패턴"으로 컴파일하고 키워드 토큰과 대조한다.
///
/// 토큰(키워드)과 패턴은 모두 UInt32 배열로 인코딩된다.
/// - 한글 음절: `syllableFlag | cho<<16 | jung<<8 | jong`
/// - 그 외 문자: 소문자화한 유니코드 스칼라 값 (0x10FFFF 이하이므로 flag 비트와 겹치지 않음)
///
/// 패턴 원소는 (mask, value) 쌍이며 `(unit & mask) == value` 면 일치.
/// - 낱자음(ㄱ) → 초성만 비교 → 초성 검색
/// - 낱모음(ㅏ) → 중성만 비교
/// - 마지막 글자에 종성이 없으면 종성은 와일드카드 → "기쁘" 입력 중에도 "기쁨" 매칭
/// - 그 외 음절/문자는 완전 일치
public struct HangulPattern: Equatable {
    public struct Element: Equatable {
        public var mask: UInt32
        public var value: UInt32
    }

    /// 매칭 등급. 값이 작을수록 좋은 매칭.
    public enum MatchTier: Int, Comparable, CaseIterable {
        /// 키워드 전체와 일치
        case exact = 0
        /// 키워드의 접두
        case prefix
        /// 키워드 안의 단어(공백 뒤) 접두
        case wordPrefix
        /// 키워드가 검색어의 접두 ("사랑해" 입력 → 키워드 "사랑"). 자동 팝업에서 조사 붙은 단어 처리용.
        case keywordIsPrefix
        /// 키워드 중간 부분 일치
        case substring

        public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
    }

    static let syllableFlag: UInt32 = 1 << 24
    static let choMask: UInt32 = 0xFF << 16
    static let jungMask: UInt32 = 0xFF << 8
    static let jongMask: UInt32 = 0xFF
    static let fullMask: UInt32 = 0xFFFF_FFFF
    static let space: UInt32 = 0x20

    public let elements: [Element]
    /// 패턴에 포함된 한글 글자(음절·자모) 수
    public let hangulCount: Int

    public var isEmpty: Bool { elements.isEmpty }
    public var count: Int { elements.count }

    // MARK: 인코딩

    @inline(__always)
    static func encodeScalar(_ s: Unicode.Scalar) -> UInt32 {
        if let syl = Hangul.decompose(scalar: s) {
            return syllableFlag | UInt32(syl.cho) << 16 | UInt32(syl.jung) << 8 | UInt32(syl.jong)
        }
        let v = s.value
        if v >= 0x41 && v <= 0x5A { return v + 0x20 } // A-Z → a-z
        return v
    }

    /// 키워드 토큰 인코딩.
    public static func encode(_ text: String) -> [UInt32] {
        var out = [UInt32]()
        out.reserveCapacity(text.unicodeScalars.count)
        for s in text.unicodeScalars { out.append(encodeScalar(s)) }
        return out
    }

    /// 검색어 컴파일. 앞뒤 공백은 제거.
    public static func compile(_ query: String) -> HangulPattern {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = Array(trimmed.unicodeScalars)
        var elements = [Element]()
        elements.reserveCapacity(scalars.count)
        var hangul = 0
        for (i, s) in scalars.enumerated() {
            let isLast = i == scalars.count - 1
            if let syl = Hangul.decompose(scalar: s) {
                hangul += 1
                var mask = fullMask
                if isLast && syl.jong == 0 { mask = syllableFlag | choMask | jungMask }
                let value = syllableFlag | UInt32(syl.cho) << 16 | UInt32(syl.jung) << 8 | UInt32(syl.jong)
                elements.append(Element(mask: mask, value: value & mask))
            } else if Hangul.isCompatibilityJamo(s) {
                hangul += 1
                let ch = Character(s)
                if let cho = Hangul.choseongIndex(of: ch) {
                    elements.append(Element(mask: syllableFlag | choMask, value: syllableFlag | UInt32(cho) << 16))
                } else if let jung = Hangul.jungseongIndex(of: ch) {
                    elements.append(Element(mask: syllableFlag | jungMask, value: syllableFlag | UInt32(jung) << 8))
                } else if let jong = Hangul.jongseongIndex(of: ch) {
                    // ㄳ 같은 종성 전용 자음
                    elements.append(Element(mask: syllableFlag | jongMask, value: syllableFlag | UInt32(jong)))
                } else {
                    elements.append(Element(mask: fullMask, value: s.value))
                }
            } else {
                elements.append(Element(mask: fullMask, value: encodeScalar(s)))
            }
        }
        return HangulPattern(elements: elements, hangulCount: hangul)
    }

    // MARK: 매칭

    /// 토큰과 대조해 가장 좋은 등급을 돌려준다. 불일치면 nil.
    public func match(in units: [UInt32]) -> MatchTier? {
        let m = elements.count
        let n = units.count
        guard m > 0 else { return nil }

        if m > n {
            // 키워드가 검색어보다 짧다: 키워드 전체가 검색어의 접두인지 본다. 1글자 키워드는 제외(잡음).
            guard n >= 2 else { return nil }
            var j = 0
            while j < n {
                if (units[j] & elements[j].mask) != elements[j].value { return nil }
                j += 1
            }
            return .keywordIsPrefix
        }

        var start = 0
        let lastStart = n - m
        while start <= lastStart {
            var j = 0
            var ok = true
            while j < m {
                if (units[start + j] & elements[j].mask) != elements[j].value { ok = false; break }
                j += 1
            }
            if ok {
                if start == 0 { return m == n ? .exact : .prefix }
                if units[start - 1] == HangulPattern.space { return .wordPrefix }
                return .substring
            }
            start += 1
        }
        return nil
    }
}
