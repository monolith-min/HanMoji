import Carbon
import Foundation

/// Carbon RegisterEventHotKey 기반 글로벌 단축키. 접근성 권한 없이 동작하고 키 이벤트를 소비한다.
final class HotKeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x484D_4F4A // "HMOJ"

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let h = handlerRef { RemoveEventHandler(h) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger?() }
            return noErr
        }, 1, &spec, userData, &handlerRef)
        if status != noErr { Log.error("InstallEventHandler failed: \(status)") }
    }

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            Log.error("RegisterEventHotKey failed (\(status)) for \(combo.displayString)")
            return false
        }
        Log.info("hotkey registered: \(combo.displayString)")
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
