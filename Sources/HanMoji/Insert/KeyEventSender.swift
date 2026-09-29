import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// CGEvent로 키 입력을 만든다. 우리가 만든 이벤트는 `marker`를 달아 tap에서 걸러낸다.
enum KeyEventSender {
    static let marker: Int64 = 0x0048_414E_4D4F_4A00 // "HANMOJ"

    private static let source: CGEventSource? = {
        let s = CGEventSource(stateID: .combinedSessionState)
        s?.userData = marker
        return s
    }()

    static func tapKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func backspace(times: Int) {
        for _ in 0..<max(0, times) { tapKey(CGKeyCode(kVK_Delete)) }
    }

    static func commandV() {
        tapKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    /// 유니코드 문자열 직접 입력. 이벤트당 UTF-16 20단위 제한이 있어 나눠 보낸다 (서로게이트 쌍은 쪼개지 않음).
    static func typeUnicode(_ text: String) {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + 20, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[start..<end])
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
            chunk.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            start = end
        }
    }
}
