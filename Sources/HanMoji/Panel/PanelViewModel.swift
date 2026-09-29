import Combine
import Foundation
import HanMojiCore

final class PanelViewModel: ObservableObject {
    @Published private(set) var results: [EmojiEntry] = []
    @Published var selectedIndex = 0
    @Published var canPaste = true

    let columns = 8
    let limit = 48

    var onSelect: ((EmojiEntry) -> Void)?
    var onCancel: (() -> Void)?

    private let engine: SearchEngine
    private let recents: RecentStore

    init(engine: SearchEngine, recents: RecentStore) {
        self.engine = engine
        self.recents = recents
    }

    var selectedEntry: EmojiEntry? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func update(query: String) {
        results = engine.search(query, recents: recents.items, options: SearchOptions(limit: limit))
        selectedIndex = 0
    }

    func move(dx: Int, dy: Int) {
        let count = results.count
        guard count > 0 else { return }
        var index = selectedIndex
        if dx != 0 { index = max(0, min(count - 1, index + dx)) }
        if dy != 0 {
            let target = index + dy * columns
            if target >= 0 && target < count {
                index = target
            } else if dy > 0, index / columns < (count - 1) / columns {
                index = count - 1
            } else if dy < 0, target < 0 {
                index = index % columns
            }
        }
        selectedIndex = index
    }

    func confirm() {
        guard let entry = selectedEntry else { return }
        onSelect?(entry)
    }

    func pick(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        confirm()
    }

    func cancel() {
        onCancel?()
    }
}
