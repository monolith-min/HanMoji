import AppKit
import Combine
import HanMojiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let recents = RecentStore()
    private let permissions = PermissionManager()
    private let inputSource = InputSourceMonitor()
    private let frontmost = FrontmostAppTracker()
    private let inserter = EmojiInserter()

    private var engine: SearchEngine!
    private var statusBar: StatusBarController!
    private var hotKeys: HotKeyManager!
    private var tap: KeystrokeTap!
    private var tracker: TypingTracker!
    private var overlay: SuggestionOverlayController!
    private var panel: SearchPanelController!
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let t0 = Date()
            let db = try EmojiDataLoader.load()
            engine = SearchEngine(database: db)
            Log.info("loaded \(db.entries.count) emojis (\(db.version)) in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "이모지 데이터를 불러올 수 없습니다"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        // 자동 팝업 경로: 키 입력 감시 → 단어 추적 → 오버레이
        overlay = SuggestionOverlayController()
        tracker = TypingTracker(engine: engine, recents: recents, settings: settings, inputSource: inputSource)
        tracker.onShow = { [weak self] word, items, highlight in
            guard let self else { return }
            let anchor = CaretLocator.locate()
            Log.info("suggest '\(word)' → \(items.map(\.emoji).joined()) anchor=\(anchor.kind)")
            self.overlay.show(items: items, highlight: highlight, anchor: anchor)
        }
        tracker.onHighlight = { [weak self] i in self?.overlay.setHighlight(i) }
        tracker.onHide = { [weak self] in self?.overlay.hide() }
        tracker.onCommit = { [weak self] entry, deletions in
            guard let self else { return }
            Log.info("insert \(entry.emoji) (delete \(deletions) keystrokes)")
            self.inserter.replaceTypedWord(with: entry.emoji, deletions: deletions, method: self.settings.insertMethod)
        }
        tracker.isPointInsideOverlay = { [weak self] point in self?.overlay.contains(cgPoint: point) ?? false }
        overlay.onPick = { [weak self] index in self?.tracker.commit(index: index) }

        tap = KeystrokeTap()
        tap.handler = { [weak self] event, type in
            self?.tracker.handle(event, type: type) ?? false
        }

        // 단축키 검색 패널 (보조 경로)
        panel = SearchPanelController(engine: engine, recents: recents, settings: settings,
                                      permissions: permissions, inserter: inserter)
        tracker.shouldIgnoreKeys = { [weak self] in self?.panel.isVisible ?? false }
        panel.onWillShow = { [weak self] in self?.tracker.resetWord() }
        hotKeys = HotKeyManager()
        hotKeys.onTrigger = { [weak self] in self?.panel.toggle() }
        hotKeys.register(settings.hotKey)

        statusBar = StatusBarController(actions: .init(
            togglePanel: { [weak self] in self?.panel.toggle() },
            toggleAutoPopup: { [weak self] in self?.settings.autoPopupEnabled.toggle() },
            toggleExcludeApp: { [weak self] app in
                guard let self, let bid = app.bundleIdentifier else { return }
                self.settings.toggleExcluded(bundleID: bid)
                self.tracker.resetWord()
            },
            requestPermission: { [weak self] in self?.permissions.requestAccess() },
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) }
        ))
        statusBar.currentAppProvider = { [weak self] in self?.frontmost.current }
        statusBar.isExcludedProvider = { [weak self] bid in self?.settings.isExcluded(bundleID: bid) ?? false }
        statusBar.setHotKeyLabel(settings.hotKey.displayString)

        frontmost.onChange = { [weak self] _ in self?.tracker.appDidSwitch() }
        inputSource.onChange = { [weak self] mode in
            Log.info("input source → \(mode)")
            self?.tracker.resetWord()
        }

        settings.$hotKey.dropFirst().removeDuplicates().sink { [weak self] combo in
            self?.hotKeys.register(combo)
            self?.statusBar.setHotKeyLabel(combo.displayString)
        }.store(in: &cancellables)
        settings.$autoPopupEnabled.dropFirst().sink { [weak self] _ in
            self?.tracker.resetWord()
            self?.updateStatusState()
        }.store(in: &cancellables)
        permissions.$isTrusted.sink { [weak self] trusted in
            guard let self else { return }
            if trusted { self.startTapIfNeeded() } else { self.tap.stop() }
            self.updateStatusState()
        }.store(in: &cancellables)
        permissions.startMonitoring()

        if !permissions.isTrusted && !settings.didPromptPermission {
            settings.didPromptPermission = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.permissions.showOnboardingAlert()
            }
        }
        Log.info("HanMoji ready. trusted=\(permissions.isTrusted) inputSource=\(inputSource.sourceID) mode=\(inputSource.mode)")
    }

    private func startTapIfNeeded() {
        guard !tap.isRunning else { return }
        if tap.start() {
            Log.info("event tap started")
        } else {
            Log.error("event tap failed to start (permission?)")
        }
    }

    private func updateStatusState() {
        if !permissions.isTrusted {
            statusBar.setState(.noPermission)
        } else if !settings.autoPopupEnabled {
            statusBar.setState(.paused)
        } else {
            statusBar.setState(.normal)
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, permissions: permissions,
                                                      dataVersion: engine.database.version,
                                                      onClearRecents: { [weak self] in self?.recents.clear() })
        }
        settingsWindow?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap?.stop()
        hotKeys?.unregister()
    }
}
