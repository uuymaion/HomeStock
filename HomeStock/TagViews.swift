import SwiftUI

// 設定頁的標籤管理：新增、刪除（標籤是全家共用的）
struct TagManageView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var kind: TagKind = .category

    private var tags: [ItemTag] {
        store.tags.filter { $0.kind == kind }
    }

    var body: some View {
        List {
            Section {
                Picker("類型", selection: $kind) {
                    ForEach(TagKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            Section {
                AddRow(placeholder: "新增\(kind.title)") { name in
                    _ = store.addTag(name: name, kind: kind)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach(tags) { tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Text("\(usage(tag)) 個物品")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("已記錄的\(kind.title)")
            } footer: {
                Text("左滑可以刪除。標籤是全家共用的，刪除後所有人的物品都會拿掉這個標籤，物品本身不會被刪除。")
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("標籤管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func usage(_ tag: ItemTag) -> Int {
        store.items.filter { $0.tagIds.contains(tag.id) }.count
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { tags[$0] }
        for tag in targets {
            store.deleteTag(tag)
        }
    }
}
