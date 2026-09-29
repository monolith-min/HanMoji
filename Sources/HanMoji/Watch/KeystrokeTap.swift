import CoreGraphics
import Foundation

/// 세션 수준 CGEventTap. 키 다운과 마우스 클릭을 받고, 핸들러가 true를 돌려주면 이벤트를 삼킨다.
/// 콜백은 메인 런루프에서 실행된다. 핸들러는 빨리 끝나야 한다 (느리면 macOS가 tap을 비활성화).
final class KeystrokeTap {
    typealias Handler = (CGEvent, CGEventType) -> Bool

    var handler: Handler?
    private(set) var isRunning = false
    fileprivate let debug = ProcessInfo.processInfo.environment["HANMOJI_DEBUG"] != nil
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeystrokeTap>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Log.warn("event tap disabled (\(type.rawValue)); re-enabling")
                tap.reenable()
                return Unmanaged.passUnretained(event)
            }
            // 우리가 보낸 이벤트(Backspace, ⌘V)는 그대로 통과
            if event.getIntegerValueField(.eventSourceUserData) == KeyEventSender.marker {
                return Unmanaged.passUnretained(event)
            }
            if tap.debug { Log.info("tap event type=\(type.rawValue) src=\(event.getIntegerValueField(.eventSourceUserData))") }
            if tap.handler?(event, type) == true { return nil }
            return Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        isRunning = false
        Log.info("event tap stopped")
    }

    private func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }
}
