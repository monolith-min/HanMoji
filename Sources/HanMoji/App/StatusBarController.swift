import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    struct Actions {
        var togglePanel: () -> Void
        var toggleAutoPopup: () -> Void
        var toggleExcludeApp: (NSRunningApplication) -> Void
        var requestPermission: () -> Void
        var openSettings: () -> Void
        var quit: () -> Void
    }

    enum State {
        case normal, paused, noPermission
    }

    /// 메뉴가 열릴 때 "현재 앱"을 알려주는 공급자 (우리 앱 자신은 제외된 최근 활성 앱)
    var currentAppProvider: (() -> NSRunningApplication?)?
    var isExcludedProvider: ((String) -> Bool)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let actions: Actions
    private let menu = NSMenu()
    private let stateItem = NSMenuItem()
    private let panelItem = NSMenuItem()
    private let autoPopupItem = NSMenuItem()
    private let excludeItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private var currentApp: NSRunningApplication?

    init(actions: Actions) {
        self.actions = actions
        super.init()
        buildMenu()
        item.menu = menu
        setState(.normal)
    }

    private func buildMenu() {
        menu.delegate = self

        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        panelItem.title = "이모지 검색 패널"
        panelItem.target = self
        panelItem.action = #selector(togglePanel)
        menu.addItem(panelItem)

        autoPopupItem.title = "자동 팝업"
        autoPopupItem.target = self
        autoPopupItem.action = #selector(toggleAutoPopup)
        menu.addItem(autoPopupItem)

        excludeItem.target = self
        excludeItem.action = #selector(toggleExclude)
        menu.addItem(excludeItem)
        menu.addItem(.separator())

        permissionItem.title = "접근성 권한 설정…"
        permissionItem.target = self
        permissionItem.action = #selector(requestPermission)
        menu.addItem(permissionItem)

        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "HanMoji 종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func setState(_ state: State) {
        let symbol: String
        let tip: String
        switch state {
        case .normal:
            symbol = "face.smiling"; tip = "HanMoji: 자동 팝업 켬"
        case .paused:
            symbol = "face.dashed"; tip = "HanMoji: 자동 팝업 꺼짐"
        case .noPermission:
            symbol = "exclamationmark.triangle"; tip = "HanMoji: 접근성 권한 필요"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HanMoji")
        item.button?.toolTip = tip
        stateItem.title = tip
        permissionItem.isHidden = state != .noPermission
        autoPopupItem.state = state == .paused ? .off : .on
    }

    func setHotKeyLabel(_ label: String) {
        panelItem.title = "이모지 검색 패널  \(label)"
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        currentApp = currentAppProvider?()
        if let app = currentApp, let bid = app.bundleIdentifier {
            let name = app.localizedName ?? bid
            let excluded = isExcludedProvider?(bid) ?? false
            excludeItem.title = excluded ? "\(name)에서 자동 팝업 다시 켜기" : "\(name)에서 자동 팝업 끄기"
            excludeItem.isHidden = false
        } else {
            excludeItem.isHidden = true
        }
    }

    // MARK: Actions

    @objc private func togglePanel() { actions.togglePanel() }
    @objc private func toggleAutoPopup() { actions.toggleAutoPopup() }
    @objc private func toggleExclude() { if let app = currentApp { actions.toggleExcludeApp(app) } }
    @objc private func requestPermission() { actions.requestPermission() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func quit() { actions.quit() }
}
