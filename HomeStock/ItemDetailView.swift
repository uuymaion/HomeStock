import SwiftUI

// 物品詳情：查看、按「已使用」、調整數量、編輯、刪除
struct ItemDetailView: View {
    let itemId: String

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        if let item = store.item(itemId) {
            content(item)
        } else {
            Text("這個物品已被刪除")
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    private func content(_ item: Item) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name)
                        .font(.title2.bold())
                    StatusBadges(item: item)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Theme.card)

            infoSection(item)
            if item.expiryDate != nil { expirySection(item) }
            if item.usageIntervalDays != nil { usageSection(item) }
            if item.quantity != nil { quantitySection(item) }

            Section {
                Button("刪除這個物品", role: .destructive) {
                    confirmDelete = true
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編輯") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                ItemFormView(editing: item)
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
        .confirmationDialog("確定要刪除「\(item.name)」嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                dismiss()
                store.deleteItem(item)
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 區塊

    private func infoSection(_ item: Item) -> some View {
        Section("分類與位置") {
            LabeledContent("大分類", value: store.category(of: item)?.name ?? "未分類")
            let subs = store.subTags(of: item)
            if !subs.isEmpty {
                LabeledContent("小標籤", value: subs.map(\.name).joined(separator: "、"))
            }
            let brands = store.brands(of: item)
            if !brands.isEmpty {
                LabeledContent("品牌", value: brands.map(\.name).joined(separator: "、"))
            }
            LabeledContent("位置", value: store.placementText(item.placement) ?? "未指定")
            LabeledContent("誰看得到", value: item.shared ? "全家" : "只有\(store.memberName(item.ownerUid))")
        }
        .listRowBackground(Theme.card)
    }

    private func expirySection(_ item: Item) -> some View {
        Section("有效日期") {
            if let expiry = item.expiryDate {
                LabeledContent("到期日", value: expiry.formatted(date: .numeric, time: .omitted))
            }
            if let days = item.daysUntilExpiry {
                LabeledContent("狀態", value: days < 0 ? "已過期 \(-days) 天" : (days == 0 ? "今天到期" : "還有 \(days) 天"))
            }
            LabeledContent("通知", value: "提前 \(item.expiryNotifyDaysBefore) 天")
        }
        .listRowBackground(Theme.card)
    }

    private func usageSection(_ item: Item) -> some View {
        Section("使用週期") {
            LabeledContent("頻率", value: item.intervalText ?? "")
            LabeledContent("上次使用", value: (item.lastUsedDate ?? item.createdAt).formatted(date: .numeric, time: .omitted))
            if let next = item.nextUseDate {
                LabeledContent("下次", value: next.formatted(date: .numeric, time: .omitted))
            }
            Button {
                store.markUsed(item)
            } label: {
                Label("已使用（重新計時）", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Theme.card)
    }

    private func quantitySection(_ item: Item) -> some View {
        Section("數量") {
            HStack {
                Button {
                    store.changeQuantity(item, by: -1)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title)
                }
                .buttonStyle(.borderless)
                .disabled((item.quantity ?? 0) <= 0)

                Spacer()
                Text("\(item.quantity ?? 0)")
                    .font(.title.bold())
                    .monospacedDigit()
                Spacer()

                Button {
                    store.changeQuantity(item, by: 1)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
                .buttonStyle(.borderless)
            }
            if let threshold = item.restockThreshold {
                LabeledContent("補貨提醒", value: "剩 \(threshold) 個以下")
            }
        }
        .listRowBackground(Theme.card)
    }
}
