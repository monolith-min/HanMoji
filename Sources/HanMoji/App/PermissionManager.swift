import AppKit
import ApplicationServices
import Combine

/// 손쉬운 사용(접근성) 권한 상태. 키 입력 감시(CGEventTap)와 ⌘V 시뮬레이션 모두 이 권한이 필요하다.
final class PermissionManager: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()
    private var timer: Timer?

    @discardableResult
    func refresh() -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            Log.info("accessibility trusted → \(trusted)")
        }
        return trusted
    }

    func startMonitoring(interval: TimeInterval = 2) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 시스템 프롬프트(앱을 목록에 추가해 줌) + 설정 패널 열기
    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openSystemSettings()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func showOnboardingAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "HanMoji에 손쉬운 사용(접근성) 권한이 필요합니다"
        alert.informativeText = """
        HanMoji는 입력 중인 한글 단어를 인식해 이모지 후보를 띄우고, 선택한 이모지를 현재 커서 위치에 넣습니다. \
        이를 위해 키 입력 감시와 ⌘V 시뮬레이션에 접근성 권한이 필요합니다.

        키 입력은 메모리에서 단어 단위로만 처리되며 저장되거나 외부로 전송되지 않습니다. \
        비밀번호 입력란은 macOS 보안 입력 모드에 의해 자동으로 제외됩니다.

        권한이 없으면 자동 팝업은 동작하지 않고, 단축키 검색 패널에서 클립보드 복사만 가능합니다.
        """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccess()
        }
    }
}
