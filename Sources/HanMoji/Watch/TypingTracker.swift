import AppKit
import Carbon.HIToolbox
import HanMojiCore

/// 키 입력 스트림에서 "지금 치고 있는 단어"를 추적하고, 후보가 있으면 오버레이를 띄우고,
/// 오버레이가 떠 있는 동안 Tab/←→/Esc(옵션: Enter)를 가로챈다.
///
/// 모든 메서드는 메인 스레드(tap 콜백)에서 호출된다. 콜백은 `DispatchQueue.main.async`로 넘겨
/// tap 콜백이 즉시 반환되게 한다 (AX 조회 등 느린 작업은 콜백 밖에서).
final class TypingTracker {
    /// (입력 중인 단어, 후보, 강조 인덱스)
    var onShow: ((String, [EmojiEntry], Int) -> Void)?
    var onHighlight: ((Int) -> Void)?
    var onHide: (() -> Void)?
    /// (선택한 이모지, 지워야 할 Backspace 수)
    var onCommit: ((EmojiEntry, Int) -> Void)?
    /// CG 좌표(좌상단 원점)의 점이 오버레이 안인지
    var isPointInsideOverlay: ((CGPoint) -> Bool)?
    /// true면 키 입력을 추적하지 않는다 (검색 패널이 키보드를 받고 있을 때).
    /// nonactivating 패널이 키 윈도우여도 이벤트의 대상 PID는 활성 앱으로 찍히므로 PID로는 구분할 수 없다.
    var shouldIgnoreKeys: (() -> Bool)?

    private let engine: SearchEngine
    private let recents: RecentStore
    private let settings: AppSettings
    private let inputSource: InputSourceMonitor

    private var composer = HangulComposer()
    private var latinWord = ""
    private var wordMode: InputSourceMonitor.Mode?
    private var dismissedForCurrentWord = false
    private(set) var suggestions: [EmojiEntry] = []
    private(set) var highlight = 0
    private(set) var isShowing = false
    private var targetPID: pid_t = 0
    private var bundleIDCache: [pid_t: String] = [:]
    private let debug = ProcessInfo.processInfo.environment["HANMOJI_DEBUG"] != nil

    init(engine: SearchEngine, recents: RecentStore, settings: AppSettings, inputSource: InputSourceMonitor) {
        self.engine = engine
        self.recents = recents
        self.settings = settings
        self.inputSource = inputSource
    }

    private var currentWord: String {
        wordMode == .latin ? latinWord : composer.text
    }

    // MARK: 이벤트 처리

    /// tap 콜백. true면 이벤트를 삼킨다.
    func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .leftMouseDown || type == .rightMouseDown {
            if isShowing, isPointInsideOverlay?(event.location) == true { return false }
            resetWord()
            return false
        }
        guard type == .keyDown else { return false }
        if shouldIgnoreKeys?() == true {
            if !composer.isEmpty || !latinWord.isEmpty || isShowing { resetWord() }
            return false
        }

        var pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid == 0 { pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }
        if pid == ProcessInfo.processInfo.processIdentifier { return false }

        guard settings.autoPopupEnabled else {
            if !composer.isEmpty || !latinWord.isEmpty { resetWord() }
            return false
        }
        if pid != targetPID {
            resetWord()
            targetPID = pid
        }
        if settings.isExcluded(bundleID: bundleID(for: pid)) { return false }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if debug {
            let ch = inputSource.character(forKeyCode: keyCode, shift: flags.contains(.maskShift)).map(String.init) ?? "nil"
            Log.info("key code=\(keyCode) flags=\(String(flags.rawValue, radix: 16)) pid=\(pid) mode=\(inputSource.mode) char=\(ch) word='\(currentWord)' showing=\(isShowing)")
        }
        if flags.contains(.maskCommand) || flags.contains(.maskControl) ||
            flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
            resetWord()
            return false
        }

        switch keyCode {
        case kVK_Tab:
            if isShowing { commitHighlighted(); return true }
            resetWord(); return false
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if isShowing, settings.enterSelects { commitHighlighted(); return true }
            resetWord(); return false
        case kVK_Escape:
            if isShowing { dismissedForCurrentWord = true; hideOverlay(); return true }
            resetWord(); return false
        case kVK_LeftArrow:
            if isShowing { moveHighlight(-1); return true }
            resetWord(); return false
        case kVK_RightArrow:
            if isShowing { moveHighlight(1); return true }
            resetWord(); return false
        case kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Space:
            resetWord(); return false
        case kVK_Delete:
            handleBackspace()
            return false
        default:
            break
        }

        let mode = inputSource.mode
        if let wordMode, wordMode != mode { resetWord() }

        let shift = flags.contains(.maskShift)
        guard let ch = inputSource.character(forKeyCode: keyCode, shift: shift) else {
            resetWord()
            return false
        }

        switch mode {
        case .korean2Set:
            // 한글 IM의 키 레이아웃은 자모를 직접 돌려주고, 라틴 레이아웃 위의 서드파티 IM은 라틴 문자를 돌려준다.
            let jamo: Character? = (Hangul.isConsonantJamo(ch) || Hangul.isVowelJamo(ch))
                ? ch : Dubeolsik.jamo(forLatin: ch, shift: shift)
            if let jamo {
                wordMode = mode
                composer.input(jamo)
                refreshSuggestions()
            } else {
                resetWord() // 숫자, 문장부호 → 단어 경계
            }
        case .latin where settings.englishTrigger:
            if ch.isLetter {
                wordMode = mode
                latinWord.append(ch)
                refreshSuggestions()
            } else {
                resetWord()
            }
        default:
            resetWord()
        }
        return false
    }

    private func handleBackspace() {
        switch wordMode {
        case .korean2Set:
            composer.backspace()
            if composer.isEmpty { resetWord() } else { refreshSuggestions() }
        case .latin:
            if !latinWord.isEmpty { latinWord.removeLast() }
            if latinWord.isEmpty { resetWord() } else { refreshSuggestions() }
        default:
            resetWord()
        }
    }

    // MARK: 후보

    private func refreshSuggestions() {
        guard !dismissedForCurrentWord else { return }
        let items = engine.suggestions(forTypedWord: currentWord, recents: recents.items,
                                       minLength: settings.minWordLength,
                                       allowKeywordPrefix: settings.matchKeywordPrefix,
                                       limit: settings.maxSuggestions)
        if items.isEmpty {
            suggestions = []
            if isShowing { hideOverlay() }
            return
        }
        suggestions = items
        highlight = 0
        isShowing = true
        let snapshot = items
        let word = currentWord
        DispatchQueue.main.async { [weak self] in self?.onShow?(word, snapshot, 0) }
    }

    private func moveHighlight(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        let count = suggestions.count
        highlight = ((highlight + delta) % count + count) % count
        let h = highlight
        DispatchQueue.main.async { [weak self] in self?.onHighlight?(h) }
    }

    private func hideOverlay() {
        guard isShowing else { return }
        isShowing = false
        DispatchQueue.main.async { [weak self] in self?.onHide?() }
    }

    private func commitHighlighted() {
        commit(index: highlight)
    }

    /// 오버레이 클릭 또는 키로 후보 확정.
    func commit(index: Int) {
        guard isShowing, suggestions.indices.contains(index) else {
            resetWord()
            return
        }
        let entry = suggestions[index]
        let deletions = wordMode == .latin ? latinWord.count : composer.deletionKeystrokes
        resetWord()
        recents.record(entry.emoji)
        DispatchQueue.main.async { [weak self] in self?.onCommit?(entry, deletions) }
    }

    // MARK: 상태 초기화

    func resetWord() {
        composer.reset()
        latinWord = ""
        wordMode = nil
        dismissedForCurrentWord = false
        suggestions = []
        highlight = 0
        hideOverlay()
    }

    func appDidSwitch() {
        resetWord()
        if bundleIDCache.count > 64 { bundleIDCache.removeAll() }
    }

    private func bundleID(for pid: pid_t) -> String? {
        if let cached = bundleIDCache[pid] { return cached }
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        bundleIDCache[pid] = bid
        return bid.isEmpty ? nil : bid
    }
}
