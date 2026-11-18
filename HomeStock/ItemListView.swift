import SwiftUI

// 主頁：所有物品列表 + 搜尋 + 篩選（查詢功能）
struct ItemListView: View {
    @EnvironmentObject private var store: HomeStore

    @State private var searchText = ""
    @State private var categoryFilter: CategoryFilter = .all
    @State private var tagFilter: Set<String> = []
    @State private var sort: SortOption = .newest
    @State private var onlyNeedsAction = false

    enum CategoryFilter: Equatable {
        case all
        case uncategorized
        case tag(String)
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "最新登錄"
        case name = "名稱"
        case urgent = "最緊急"
        var id: String { rawValue }
    }

    private var categories: [ItemTag] { store.tags.filter { $0.kind == .category } }
    private var subTags: [ItemTag] { store.tags.filter { $0.kind == .sub } }
    private var brands: [ItemTag] { store.tags.filter { $0.kind == .brand } }

    private var hasActiveFilter: Bool {
        !tagFilter.isEmpty || onlyNeedsAction
    }

    private var filtered: [Item] {
        let key = searchText.trimmed.lowercased()
        let result = store.items.filter { matches($0, key: key) }
        switch sort {
        case .newest:
            return result.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .urgent:
            return result.sorted { $0.urgencyDate < $1.urgencyDate }
        }
    }

    private func matches(_ item: Item, key: String) -> Bool {
        let categoryId = store.category(of: item)?.id
        switch categoryFilter {
        case .all:
            break
        case .uncategorized:
            if categoryId != nil { return false }
        case .tag(let id):
            if categoryId != id { return false }
        }
        if !tagFilter.isEmpty && !tagFilter.isSubset(of: Set(item.tagIds)) { return false }
        if onlyNeedsAction && item.statuses().isEmpty { return false }
        if !key.isEmpty {
            var parts = [item.name]
            parts += item.tagIds.compactMap { store.tag($0)?.name }
            if let location = store.placementText(item.placement) { parts.append(location) }
            if !parts.joined(separator: " ").lowercased().contains(key) { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    categoryBar
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if filtered.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                } else {
                    Section("\(filtered.count) 個物品") {
                        ForEach(filtered) { item in
                            NavigationLink {
                                ItemDetailView(itemId: item.id)
                            } label: {
                                ItemRow(item: item)
                            }
                            .listRowBackground(Theme.card)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .themedList()
            .navigationTitle(store.family?.name ?? "家裡的東西")
            .searchable(text: $searchText, prompt: "搜尋名稱、標籤、位置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
        }
    }

    // MARK: - 子畫面

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip("全部", filter: .all)
                ForEach(categories) { tag in
                    categoryChip(tag.name, filter: .tag(tag.id))
                }
                categoryChip("未分類", filter: .uncategorized)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(_ title: String, filter: CategoryFilter) -> some View {
        Button {
            categoryFilter = filter
        } label: {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(categoryFilter == filter ? Color.white : Theme.subtext)
                .background(
                    Capsule().fill(categoryFilter == filter ? Theme.accent : Theme.card)
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentSoft)
            Text(store.items.isEmpty ? "還沒有登錄任何物品" : "沒有符合條件的物品")
                .foregroundStyle(Theme.subtext)
            if store.items.isEmpty {
                Text("到下方「登錄」分頁新增第一個物品")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var filterMenu: some View {
        Menu {
            Picker("排序", selection: $sort) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            Toggle("只看需要處理的", isOn: $onlyNeedsAction)

            if !subTags.isEmpty {
                Menu("小標籤") {
                    ForEach(subTags) { tag in tagToggle(tag) }
                }
            }
            if !brands.isEmpty {
                Menu("品牌") {
                    ForEach(brands) { tag in tagToggle(tag) }
                }
            }
            if hasActiveFilter {
                Button("清除篩選", role: .destructive) {
                    tagFilter.removeAll()
                    onlyNeedsAction = false
                }
            }
        } label: {
            Image(systemName: hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private func tagToggle(_ tag: ItemTag) -> some View {
        Button {
            if tagFilter.contains(tag.id) {
                tagFilter.remove(tag.id)
            } else {
                tagFilter.insert(tag.id)
            }
        } label: {
            if tagFilter.contains(tag.id) {
                Label(tag.name, systemImage: "checkmark")
            } else {
                Text(tag.name)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { filtered[$0] }
        for item in targets {
            store.deleteItem(item)
        }
    }
}

// MARK: - 列表的一列

struct ItemRow: View {
    @EnvironmentObject private var store: HomeStore
    let item: Item

    private var metaText: String {
        var parts: [String] = [store.category(of: item)?.name ?? "未分類"]
        parts += store.brands(of: item).map(\.name)
        parts += store.subTags(of: item).map(\.name)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardHigh)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: item.shared ? "shippingbox" : "lock.fill")
                        .foregroundStyle(Theme.accentSoft)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                    Spacer()
                    if let quantity = item.quantity {
                        Text("×\(quantity)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
                if let location = store.placementText(item.placement) {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
                StatusBadges(item: item)
            }
        }
        .padding(.vertical, 4)
    }
}
