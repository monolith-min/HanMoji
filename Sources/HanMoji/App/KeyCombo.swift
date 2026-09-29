import AppKit
import Carbon.HIToolbox

/// 글로벌 단축키 조합. UserDefaults에 JSON으로 저장된다.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// NSEvent.ModifierFlags rawValue (⌘⌥⌃⇧만)
    var modifierFlags: UInt
    var keyLabel: String

    static let `default` = KeyCombo(keyCode: UInt32(kVK_Space),
                                    modifierFlags: NSEvent.ModifierFlags([.control, .option]).rawValue,
                                    keyLabel: "Space")

    init(keyCode: UInt32, modifierFlags: UInt, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifierFlags = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
        keyLabel = KeyCombo.label(for: event)
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection([.command, .option, .control, .shift])
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        let f = flags
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var displayString: String {
        var s = ""
        let f = flags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + keyLabel
    }

    private static let specialLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func label(for event: NSEvent) -> String {
        if let s = specialLabels[Int(event.keyCode)] { return s }
        if let c = event.charactersIgnoringModifiers, !c.isEmpty,
           c.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) {
            return c.uppercased()
        }
        return "Key\(event.keyCode)"
    }
}
