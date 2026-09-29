import Carbon
import Foundation

/// 현재 키보드 입력 소스(한글 두벌식 / 라틴 / 기타)와 키코드→라틴 문자 표를 유지한다.
final class InputSourceMonitor {
    enum Mode: Equatable, CustomStringConvertible {
        case korean2Set
        case koreanOther
        case latin
        case other

        var description: String {
            switch self {
            case .korean2Set: return "korean2Set"
            case .koreanOther: return "koreanOther"
            case .latin: return "latin"
            case .other: return "other"
            }
        }
    }

    private(set) var mode: Mode = .other
    private(set) var sourceID: String = ""
    /// keyCode(0..<128) → 수식키 없이 현재 레이아웃이 만드는 문자.
    /// 한글 IM(두벌식)은 여기서 라틴 문자가 아니라 자모(ㄱ, ㅣ…)를 돌려준다.
    private(set) var baseCharacters: [Character?] = Array(repeating: nil, count: 128)
    /// keyCode → Shift를 누른 상태의 문자 (두벌식: ㅃㅉㄸㄲㅆㅒㅖ)
    private(set) var shiftedCharacters: [Character?] = Array(repeating: nil, count: 128)
    var onChange: ((Mode) -> Void)?

    init() {
        refresh()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func sourceChanged(_ note: Notification) {
        let old = (mode, sourceID)
        refresh()
        if old != (mode, sourceID) { onChange?(mode) }
    }

    func refresh() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        sourceID = Self.stringProperty(source, kTISPropertyInputSourceID) ?? ""
        mode = Self.classify(sourceID)
        baseCharacters = Self.buildKeymap(shift: false)
        shiftedCharacters = Self.buildKeymap(shift: true)
    }

    func character(forKeyCode keyCode: Int, shift: Bool) -> Character? {
        guard keyCode >= 0, keyCode < baseCharacters.count else { return nil }
        return shift ? (shiftedCharacters[keyCode] ?? baseCharacters[keyCode]) : baseCharacters[keyCode]
    }

    static func classify(_ id: String) -> Mode {
        let lower = id.lowercased()
        if lower.contains("2setkorean") || lower.contains("han2") { return .korean2Set }
        if lower.contains("korean") || lower.contains("hangul") { return .koreanOther }
        if lower.hasPrefix("com.apple.keylayout.") { return .latin }
        return .other
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// 현재 입력 소스가 사용하는 물리 레이아웃(한글 IM이면 그 아래의 라틴 레이아웃)으로 키코드→문자 표를 만든다.
    private static func buildKeymap(shift: Bool) -> [Character?] {
        var table = [Character?](repeating: nil, count: 128)
        guard let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
            return ansiFallback(shift: shift)
        }
        // UCKeyTranslate의 modifierKeyState는 (EventModifiers >> 8) & 0xFF
        let modifierState: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let keyboard = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var chars = [UniChar](repeating: 0, count: 4)
            for code in 0..<128 {
                var dead: UInt32 = 0
                var length = 0
                let err = UCKeyTranslate(keyboard, UInt16(code), UInt16(kUCKeyActionDown), modifierState,
                                         UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                         &dead, 4, &length, &chars)
                if err == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) {
                    table[code] = Character(scalar)
                }
            }
        }
        if table.compactMap({ $0 }).isEmpty { return ansiFallback(shift: shift) }
        return table
    }

    private static func ansiFallback(shift: Bool) -> [Character?] {
        var table = [Character?](repeating: nil, count: 128)
        let map: [Int: Character] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
            12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o",
            32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`",
        ]
        for (k, v) in map { table[k] = shift ? Character(v.uppercased()) : v }
        return table
    }
}
