// 개발/테스트용: HID 레벨로 키·마우스 이벤트를 보낸다. 세션 이벤트 탭을 통과하므로 HanMoji가 실제 타이핑처럼 본다.
// (AppleScript System Events의 key code는 대상 프로세스로 직접 전달돼 이벤트 탭을 거치지 않는다.)
//
// 빌드:  swiftc -O -o /tmp/keypost scripts/keypost.swift
// 사용:  /tmp/keypost [--delay ms] 토큰...
//   소문자 = 해당 키 (ANSI 배열 기준), 대문자 = Shift+키, TAB RET ESC BS SPACE LEFT RIGHT UP DOWN
//   CMD- CTRL- OPT- SHIFT- 접두로 수식키 (예: CTRL-OPT-SPACE), WAIT-<ms>, MOUSE-<x>-<y> (전역 좌표)
//   예) 한글 두벌식에서 "기쁨" 입력 후 Tab:  /tmp/keypost r l Q m a WAIT-800 TAB
import CoreGraphics
import Foundation

let ansi: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
    "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
    "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
]
let special: [String: CGKeyCode] = ["TAB": 48, "RET": 36, "ESC": 53, "BS": 51, "SPACE": 49, "LEFT": 123, "RIGHT": 124, "UP": 126, "DOWN": 125]

var args = Array(CommandLine.arguments.dropFirst())
var delayMs = 120
if let i = args.firstIndex(of: "--delay"), i + 1 < args.count { delayMs = Int(args[i + 1]) ?? 120; args.removeSubrange(i...(i + 1)) }
let src = CGEventSource(stateID: .hidSystemState)

func tap(_ code: CGKeyCode, flags: CGEventFlags) {
    let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!
    let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!
    d.flags = flags; u.flags = flags
    d.post(tap: .cghidEventTap); u.post(tap: .cghidEventTap)
}

for token in args {
    if token.hasPrefix("WAIT-"), let ms = Int(token.dropFirst(5)) { usleep(UInt32(ms * 1000)); continue }
    if token.hasPrefix("MOUSE-") {
        let parts = token.dropFirst(6).split(separator: "-").compactMap { Double($0) }
        if parts.count == 2, let mv = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: parts[0], y: parts[1]), mouseButton: .left) {
            mv.post(tap: .cghidEventTap)
        }
        usleep(UInt32(delayMs * 1000)); continue
    }
    var flags: CGEventFlags = []
    var t = token
    var changed = true
    while changed {
        changed = false
        for (prefix, flag) in [("CMD-", CGEventFlags.maskCommand), ("CTRL-", .maskControl), ("OPT-", .maskAlternate), ("SHIFT-", .maskShift)] where t.hasPrefix(prefix) {
            flags.insert(flag); t = String(t.dropFirst(prefix.count)); changed = true
        }
    }
    if let code = special[t] {
        tap(code, flags: flags)
    } else if t.count == 1, let ch = t.first {
        let lower = Character(ch.lowercased())
        guard let code = ansi[lower] else { FileHandle.standardError.write("unknown key \(t)\n".data(using: .utf8)!); continue }
        if ch.isUppercase { flags.insert(.maskShift) }
        tap(code, flags: flags)
    } else {
        FileHandle.standardError.write("unknown token \(t)\n".data(using: .utf8)!)
    }
    usleep(UInt32(delayMs * 1000))
}
