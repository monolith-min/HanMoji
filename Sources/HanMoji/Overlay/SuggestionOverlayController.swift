import AppKit
import HanMojiCore
import SwiftUI

final class SuggestionStripModel: ObservableObject {
    @Published var items: [EmojiEntry] = []
    @Published var highlight = 0
    @Published var hint = "⇥ 삽입  ←→ 선택  esc 닫기"
    var onPick: ((Int) -> Void)?

    var caption: String {
        guard items.indices.contains(highlight) else { return "" }
        let e = items[highlight]
        return e.koreanName ?? e.koreanKeywords.first ?? e.englishName
    }
}

struct SuggestionStripView: View {
    @ObservedObject var model: SuggestionStripModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(model.items.enumerated()), id: \.offset) { index, entry in
                    Text(entry.emoji)
                        .font(.system(size: 24))
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(index == model.highlight ? Color.accentColor.opacity(0.35) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.onPick?(index) }
                }
            }
            HStack(spacing: 8) {
                Text(model.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(model.hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .fixedSize()
    }
}

/// 키 윈도우가 되지 않는 오버레이 패널. 포커스는 항상 원래 앱에 남는다.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 비활성 창에서도 첫 클릭을 받아 탭 제스처가 동작하게 한다.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SuggestionOverlayController {
    private let panel = OverlayPanel()
    private let model = SuggestionStripModel()
    private let host: FirstMouseHostingView<SuggestionStripView>
    private let effect = NSVisualEffectView()

    var onPick: ((Int) -> Void)? {
        get { model.onPick }
        set { model.onPick = newValue }
    }

    var isVisible: Bool { panel.isVisible }

    init() {
        host = FirstMouseHostingView(rootView: SuggestionStripView(model: model))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    func show(items: [EmojiEntry], highlight: Int, anchor: CaretLocator.Anchor) {
        model.items = items
        model.highlight = highlight
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: anchor, size: size))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func setHighlight(_ index: Int) {
        model.highlight = index
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// CG 좌표(좌상단 원점)의 점이 오버레이 안인지
    func contains(cgPoint: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        return CaretLocator.cg(panel.frame).contains(cgPoint)
    }

    private func origin(for anchor: CaretLocator.Anchor, size: NSSize) -> NSPoint {
        let reference = anchor.rect ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: reference.midX, y: reference.midY)) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        var origin: NSPoint

        switch anchor {
        case .caret(let r):
            origin = NSPoint(x: r.minX - 12, y: r.maxY + gap)
            if origin.y + size.height > visible.maxY { origin.y = r.minY - size.height - gap }
        case .element(let r):
            origin = NSPoint(x: r.minX, y: r.maxY + gap)
            if origin.y + size.height > visible.maxY { origin.y = r.minY - size.height - gap }
        case .window(let r):
            origin = NSPoint(x: r.midX - size.width / 2, y: r.minY + 96)
        case .none:
            let m = NSEvent.mouseLocation
            origin = NSPoint(x: m.x - size.width / 2, y: m.y + 24)
        }

        origin.x = max(visible.minX + gap, min(origin.x, visible.maxX - size.width - gap))
        origin.y = max(visible.minY + gap, min(origin.y, visible.maxY - size.height - gap))
        return origin
    }
}
