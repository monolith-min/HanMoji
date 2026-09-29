import AppKit
import ApplicationServices

/// 접근성 API로 텍스트 캐럿 위치를 찾는다. 좌표는 Cocoa(좌하단 원점) 화면 좌표.
enum CaretLocator {
    enum Anchor {
        /// 캐럿(또는 캐럿 앞 글자) 사각형
        case caret(CGRect)
        /// 포커스된 텍스트 요소의 프레임
        case element(CGRect)
        /// 포커스된 창의 프레임
        case window(CGRect)
        /// 아무것도 못 찾음
        case none

        var rect: CGRect? {
            switch self {
            case .caret(let r), .element(let r), .window(let r): return r
            case .none: return nil
            }
        }

        var kind: String {
            switch self {
            case .caret: return "caret"
            case .element: return "element"
            case .window: return "window"
            case .none: return "none"
            }
        }
    }

    private static let systemWide: AXUIElement = {
        let e = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(e, 0.15)
        return e
    }()

    static func locate() -> Anchor {
        guard let focused = copyElement(systemWide, kAXFocusedUIElementAttribute) else {
            return windowAnchor()
        }
        AXUIElementSetMessagingTimeout(focused, 0.15)

        if let rangeValue = copyValue(focused, kAXSelectedTextRangeAttribute),
           var range = cfRange(rangeValue) {
            var rect = boundsForRange(focused, range)
            // 캐럿(길이 0)이 텍스트 끝에 있으면 빈 rect를 주는 앱이 있어 바로 앞 글자로 재시도
            if (rect == nil || rect!.isEmpty), range.location > 0 {
                range = CFRange(location: range.location - 1, length: 1)
                rect = boundsForRange(focused, range)
            }
            if let r = rect, !r.isEmpty, r.width < 4000, r.height < 600 {
                return .caret(cocoa(r))
            }
        }

        if let pos = copyValue(focused, kAXPositionAttribute), let size = copyValue(focused, kAXSizeAttribute),
           let p = cgPoint(pos), let s = cgSize(size), s.width > 0, s.height > 0 {
            return .element(cocoa(CGRect(origin: p, size: s)))
        }
        return windowAnchor()
    }

    private static func windowAnchor() -> Anchor {
        guard let app = copyElement(systemWide, kAXFocusedApplicationAttribute),
              let window = copyElement(app, kAXFocusedWindowAttribute),
              let pos = copyValue(window, kAXPositionAttribute), let size = copyValue(window, kAXSizeAttribute),
              let p = cgPoint(pos), let s = cgSize(size) else { return .none }
        return .window(cocoa(CGRect(origin: p, size: s)))
    }

    // MARK: AX helpers

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = copyValue(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &out)
        guard err == .success, let out else { return nil }
        return cgRect(out)
    }

    private static func cfRange(_ value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    private static func cgRect(_ value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private static func cgPoint(_ value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func cgSize(_ value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }

    /// AX(좌상단 원점, 주 화면 기준) → Cocoa(좌하단 원점)
    static func cocoa(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Cocoa → AX/CG(좌상단 원점)
    static func cg(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
