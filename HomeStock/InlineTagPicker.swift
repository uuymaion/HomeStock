import SwiftUI

// 在同一個畫面直接點選標籤（不用點進下一頁）。
// 刪除標籤仍然在「設定 › 標籤管理」。

/// 會自動換行的排列方式，標籤太多時往下一行排
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct InlineTagPicker: View {
    let kind: TagKind
    @Binding var selection: [String]      // 選到的標籤 id
    var single: Bool = false

    @EnvironmentObject private var store: HomeStore

    @State private var adding = false
    @State private var newName = ""
    @FocusState private var focused: Bool

    private var tags: [ItemTag] {
        store.tags.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.subheadline)
                .foregroundStyle(Theme.subtext)

            FlowLayout(spacing: 8) {
                if kind == .category {
                    chip("未分類", on: selection.isEmpty) {
                        selection = []
                    }
                }
                ForEach(tags) { tag in
                    chip(tag.name, on: selection.contains(tag.id)) {
                        toggle(tag.id)
                    }
                }
                addControl
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 子畫面

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : Theme.subtext)
                .background(Capsule().fill(on ? Theme.accent : Theme.cardHigh))
        }
        // 一定要加：Form 裡同一列有多個按鈕時，不加的話點一個會全部觸發
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var addControl: some View {
        if adding {
            TextField("輸入名稱", text: $newName)
                .font(.subheadline)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .onAppear { focused = true }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .frame(width: 110)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().stroke(Theme.accent, lineWidth: 1))
        } else {
            Button {
                adding = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("新增")
                }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(Theme.accent)
                    .background(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
    #imageLiteral(resourceName: "截圖 2026-11-18 上午9.18.07.png")
    // MARK: - 動作

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.removeAll { $0 == id }
        } else if single {
            selection = [id]
        } else {
            selection.append(id)
        }
    }

    /// 輸入完成：已存在的就直接選取，沒有的就新增並選取
    private func commit() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        adding = false
        guard !name.isEmpty else { return }

        // 已存在的標籤會直接回傳原本的 id
        if let id = store.addTag(name: name, kind: kind), !selection.contains(id) {
            toggle(id)
        }
    }
}
