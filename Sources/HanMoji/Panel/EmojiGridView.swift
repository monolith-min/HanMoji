import SwiftUI

struct EmojiGridView: View {
    @ObservedObject var model: PanelViewModel
    static let cell: CGFloat = 44
    static let spacing: CGFloat = 4

    var body: some View {
        if model.results.isEmpty {
            Text("결과 없음")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.spacing), count: model.columns),
                              spacing: Self.spacing) {
                        // 식별자는 인덱스 하나만 쓴다. 이모지 id + .id(index) 이중 지정 시 LazyVGrid가 셀 내용을 갱신하지 않았다.
                        ForEach(Array(model.results.enumerated()), id: \.offset) { index, entry in
                            Text(entry.emoji)
                                .font(.system(size: 26))
                                .frame(width: Self.cell, height: Self.cell)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(index == model.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { model.pick(index) }
                                .onHover { inside in if inside { model.selectedIndex = index } }
                        }
                    }
                    .padding(Self.spacing)
                }
                .onChange(of: model.selectedIndex) { _, newValue in
                    proxy.scrollTo(newValue)
                }
            }
        }
    }
}
