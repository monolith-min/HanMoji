import AppKit
import HanMojiCore
import SwiftUI

/// 앱을 활성화하지 않고 키보드 입력만 받는 패널.
final class EmojiPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelContentView: NSVisualEffectView {
    let searchField = NSTextField()
    let footerLabel = NSTextField(labelWithString: "")
    let hintLabel = NSTextField(labelWithString: "↩ 삽입   ⇥/← → ↑ ↓ 이동   esc 닫기")
    private let gridHost: NSHostingView<EmojiGridView>

    static let width: CGFloat = 8 * EmojiGridView.cell + 7 * EmojiGridView.spacing + 2 * EmojiGridView.spacing + 16
    static let gridHeight: CGFloat = 5 * EmojiGridView.cell + 4 * EmojiGridView.spacing + 2 * EmojiGridView.spacing

    init(model: PanelViewModel) {
        gridHost = NSHostingView(rootView: EmojiGridView(model: model))
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 18)
        searchField.placeholderString = "이모지 검색 (한글 · 초성 · 영어)"
        searchField.cell?.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingTail

        let separator = NSBox()
        separator.boxType = .separator

        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingTail
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right

        for v in [searchField, separator, gridHost, footerLabel, hintLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            gridHost.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            gridHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            gridHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            gridHost.heightAnchor.constraint(equalToConstant: Self.gridHeight),

            footerLabel.topAnchor.constraint(equalTo: gridHost.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            hintLabel.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: footerLabel.trailingAnchor, constant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

final class SearchPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let panel: EmojiPanel
    private let content: PanelContentView
    private let model: PanelViewModel
    private let recents: RecentStore
    private let settings: AppSettings
    private let permissions: PermissionManager
    private let inserter: EmojiInserter
    private var targetApp: NSRunningApplication?
    private var footerObserver: Any?
    /// 패널이 뜨기 직전 (자동 팝업 추적기 초기화용)
    var onWillShow: (() -> Void)?

    init(engine: SearchEngine, recents: RecentStore, settings: AppSettings,
         permissions: PermissionManager, inserter: EmojiInserter) {
        self.recents = recents
        self.settings = settings
        self.permissions = permissions
        self.inserter = inserter
        model = PanelViewModel(engine: engine, recents: recents)
        content = PanelContentView(model: model)
        panel = EmojiPanel(contentRect: NSRect(x: 0, y: 0, width: PanelContentView.width, height: 340))
        super.init()

        panel.contentView = content
        panel.delegate = self
        content.searchField.delegate = self
        model.onSelect = { [weak self] entry in self?.didSelect(entry) }
        model.onCancel = { [weak self] in self?.hide() }
        footerObserver = model.$selectedIndex.combineLatest(model.$results, model.$canPaste)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.updateFooter() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        onWillShow?()
        let me = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me {
            targetApp = front
        } else {
            targetApp = nil
        }
        model.canPaste = permissions.refresh()
        content.searchField.stringValue = ""
        model.update(query: "")
        position()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(content.searchField)
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func position() {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin: NSPoint
        switch settings.panelPlacement {
        case .nearMouse:
            origin = NSPoint(x: mouse.x - 24, y: mouse.y - size.height - 16)
            if origin.y < visible.minY { origin.y = mouse.y + 16 }
        case .screenCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 60)
        }
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        panel.setFrameOrigin(origin)
    }

    private func updateFooter() {
        if !model.canPaste {
            content.footerLabel.stringValue = "접근성 권한 없음 → 선택 시 클립보드에 복사만 합니다"
            content.footerLabel.textColor = .systemOrange
            return
        }
        content.footerLabel.textColor = .secondaryLabelColor
        if let e = model.selectedEntry {
            let keywords = e.koreanKeywords.prefix(4).joined(separator: ", ")
            content.footerLabel.stringValue = [e.koreanName ?? e.englishName, keywords].filter { !$0.isEmpty }.joined(separator: " · ")
        } else {
            content.footerLabel.stringValue = ""
        }
    }

    private func didSelect(_ entry: EmojiEntry) {
        recents.record(entry.emoji)
        let canPaste = model.canPaste
        let target = targetApp
        hide()
        if canPaste {
            inserter.insertAtCursor(entry.emoji, method: settings.insertMethod, target: target)
        } else {
            inserter.copyOnly(entry.emoji)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let query = content.searchField.stringValue
        model.update(query: query)
        if debug {
            let editor = content.searchField.currentEditor() as? NSTextView
            Log.info("panel query='\(query)' editor='\(editor?.string ?? "")' marked=\(editor?.markedRange() ?? NSRange()) results=\(model.results.count) first=\(model.results.prefix(3).map(\.emoji).joined())")
        }
    }

    private let debug = ProcessInfo.processInfo.environment["HANMOJI_DEBUG"] != nil

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            model.move(dx: 0, dy: -1)
        case #selector(NSResponder.moveDown(_:)):
            model.move(dx: 0, dy: 1)
        case #selector(NSResponder.moveLeft(_:)):
            if textView.hasMarkedText() { return false }
            model.move(dx: -1, dy: 0)
        case #selector(NSResponder.moveRight(_:)):
            if textView.hasMarkedText() { return false }
            model.move(dx: 1, dy: 0)
        case #selector(NSResponder.insertTab(_:)):
            model.move(dx: 1, dy: 0)
        case #selector(NSResponder.insertBacktab(_:)):
            model.move(dx: -1, dy: 0)
        case #selector(NSResponder.insertNewline(_:)):
            model.confirm()
        case #selector(NSResponder.cancelOperation(_:)):
            model.cancel()
        default:
            return false
        }
        return true
    }
}
