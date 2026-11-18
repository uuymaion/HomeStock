import SwiftUI

// 登錄／編輯物品的表單。
// editing 為 nil 代表新增（「登錄」分頁），有值代表編輯。
struct ItemFormView: View {
    var editing: Item? = nil

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultNotifyDays") private var defaultNotifyDays = 7

    @State private var loaded = false
    @State private var name = ""
    @State private var categorySel: [String] = []
    @State private var subSel: [String] = []
    @State private var brandSel: [String] = []
    @State private var placement = Placement()

    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var notifyDays = 7

    @State private var hasInterval = false
    @State private var intervalValue = 1
    @State private var intervalUnit: IntervalUnit = .month
    @State private var lastUsed = Date()

    @State private var hasQuantity = false
    @State private var quantity = 1
    @State private var hasThreshold = false
    @State private var threshold = 1

    @State private var showLocationPicker = false
    @State private var showSaved = false

    enum IntervalUnit: String, CaseIterable, Identifiable {
        case day = "天"
        case week = "週"
        case month = "個月"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }

    var body: some View {
        Form {
            Section("名稱（必填）") {
                TextField("名稱", text: $name)
            }
            .listRowBackground(Theme.card)

            tagSection
            locationSection
            expirySection
            intervalSection
            quantitySection
        }
        .themedList()
        .navigationTitle(editing == nil ? "登錄物品" : "編輯物品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存", action: save)
                    .disabled(name.trimmed.isEmpty)
            }
        }
        .onAppear(perform: loadIfNeeded)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet(allowBoxes: true, allowNone: true) { picked in
                placement = picked
            }
            .environmentObject(store)
        }
        .alert("已登錄", isPresented: $showSaved) {
            Button("好") {}
        } message: {
            Text("可以繼續登錄下一個物品")
        }
    }

    // MARK: - 各區塊

    private var tagSection: some View {
        Section {
            InlineTagPicker(kind: .category, selection: $categorySel, single: true)
            InlineTagPicker(kind: .sub, selection: $subSel)
            InlineTagPicker(kind: .brand, selection: $brandSel, single: true)
        } header: {
            Text("分類與標籤")
        } footer: {
            Text("點一下選取，再點一下取消。要刪除標籤請到「設定 › 標籤管理」。")
        }
        .listRowBackground(Theme.card)
    }

    private var locationSection: some View {
        Section {
            Button {
                showLocationPicker = true
            } label: {
                LabeledContent("放在哪裡", value: store.placementText(placement) ?? "未指定")
            }
            .foregroundStyle(.primary)
        } header: {
            Text("位置")
        } footer: {
            if let room = store.roomOf(placement), !room.shared {
                Text("「\(room.name)」是私人房間，只有\(store.memberName(room.ownerUid))看得到這個物品。")
            }
        }
        .listRowBackground(Theme.card)
    }

    private var expirySection: some View {
        Section("有效日期") {
            Toggle("有有效日期", isOn: $hasExpiry)
            if hasExpiry {
                DatePicker("到期日", selection: $expiryDate, displayedComponents: .date)
                Stepper("提前 \(notifyDays) 天通知", value: $notifyDays, in: 0...365)
            }
        }
        .listRowBackground(Theme.card)
    }

    private var intervalSection: some View {
        Section("使用週期") {
            Toggle("需要定期使用／更換", isOn: $hasInterval)
            if hasInterval {
                Stepper("每 \(intervalValue) \(intervalUnit.rawValue)", value: $intervalValue, in: 1...365)
                Picker("單位", selection: $intervalUnit) {
                    ForEach(IntervalUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker("上次使用日", selection: $lastUsed, in: ...Date(), displayedComponents: .date)
            }
        }
        .listRowBackground(Theme.card)
    }

    private var quantitySection: some View {
        Section("數量") {
            Toggle("記錄數量", isOn: $hasQuantity)
            if hasQuantity {
                Stepper("數量：\(quantity)", value: $quantity, in: 0...9999)
                Toggle("快用完時提醒補貨", isOn: $hasThreshold)
                if hasThreshold {
                    Stepper("剩 \(threshold) 個以下提醒", value: $threshold, in: 0...9999)
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - 讀取／儲存

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        notifyDays = defaultNotifyDays
        guard let item = editing else { return }

        name = item.name
        categorySel = store.category(of: item).map { [$0.id] } ?? []
        subSel = store.subTags(of: item).map(\.id)
        brandSel = store.brands(of: item).map(\.id)
        placement = item.placement

        if let expiry = item.expiryDate {
            hasExpiry = true
            expiryDate = expiry
            notifyDays = item.expiryNotifyDaysBefore
        }
        if let days = item.usageIntervalDays, days > 0 {
            hasInterval = true
            if days % 30 == 0 {
                intervalUnit = .month
                intervalValue = days / 30
            } else if days % 7 == 0 {
                intervalUnit = .week
                intervalValue = days / 7
            } else {
                intervalUnit = .day
                intervalValue = days
            }
            lastUsed = item.lastUsedDate ?? item.createdAt
        }
        if let q = item.quantity {
            hasQuantity = true
            quantity = q
        }
        if let t = item.restockThreshold {
            hasThreshold = true
            threshold = t
        }
    }

    private func save() {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }

        let oldQuantity = editing?.quantity
        var item = editing ?? Item(name: trimmedName)
        item.name = trimmedName

        // 過濾掉已經被刪除的標籤
        let validIds = Set(store.tags.map(\.id))
        item.tagIds = (categorySel + subSel + brandSel).filter { validIds.contains($0) }
        item.placement = placement

        item.expiryDate = hasExpiry ? Calendar.current.startOfDay(for: expiryDate) : nil
        item.expiryNotifyDaysBefore = notifyDays

        item.usageIntervalDays = hasInterval ? intervalValue * intervalUnit.days : nil
        item.lastUsedDate = hasInterval ? lastUsed : nil

        item.quantity = hasQuantity ? quantity : nil
        item.restockThreshold = (hasQuantity && hasThreshold) ? threshold : nil

        let saved = store.saveItem(item)

        if hasQuantity && hasThreshold && quantity <= threshold {
            let wasAbove = oldQuantity.map { $0 > threshold } ?? true
            if wasAbove {
                NotificationManager.shared.notifyRestock(name: saved.name, quantity: quantity, id: saved.id)
            }
        }

        if editing == nil {
            resetForm()
            showSaved = true
        } else {
            dismiss()
        }
    }

    private func resetForm() {
        name = ""
        categorySel = []
        subSel = []
        brandSel = []
        placement = Placement()
        hasExpiry = false
        expiryDate = Date()
        notifyDays = defaultNotifyDays
        hasInterval = false
        intervalValue = 1
        intervalUnit = .month
        lastUsed = Date()
        hasQuantity = false
        quantity = 1
        hasThreshold = false
        threshold = 1
    }
}
