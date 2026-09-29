import AppKit
import HanMojiCore

/// 이모지를 대상 앱에 넣는다.
/// - 자동 팝업: 입력한 단어를 Backspace로 지운 뒤 삽입
/// - 검색 패널: 현재 커서에 삽입
/// - 권한 없음: 클립보드 복사만
final class EmojiInserter {
    private let hud = HUDWindow()
    /// ⌘V 이후 클립보드 원복까지 대기. 느린 앱(Electron)이 붙여넣기를 끝낼 시간을 준다.
    var restoreDelay: TimeInterval = 0.3

    func replaceTypedWord(with emoji: String, deletions: Int, method: InsertMethod) {
        KeyEventSender.backspace(times: deletions)
        // Backspace가 IME/앱에서 처리될 시간을 조금 준다.
        let delay = 0.02 + Double(deletions) * 0.004
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.insert(emoji, method: method)
        }
    }

    func insertAtCursor(_ emoji: String, method: InsertMethod, target: NSRunningApplication?) {
        if let target, !target.isActive {
            target.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.insert(emoji, method: method)
        }
    }

    func copyOnly(_ emoji: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(emoji, forType: .string)
        hud.show("\(emoji) 복사됨 · ⌘V로 붙여넣기")
    }

    private func insert(_ emoji: String, method: InsertMethod) {
        switch method {
        case .typeUnicode:
            KeyEventSender.typeUnicode(emoji)
        case .paste:
            let pb = NSPasteboard.general
            let snapshot = PasteboardSnapshot.capture(pb)
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setString(emoji, forType: .string)
            // 클립보드 관리자들이 이 항목을 기록하지 않도록 표시
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            pb.writeObjects([item])
            let ourChange = pb.changeCount
            KeyEventSender.commandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                // 그 사이 사용자가 다른 것을 복사했다면 건드리지 않는다
                if pb.changeCount == ourChange { snapshot.restore(to: pb) }
            }
        }
    }
}
