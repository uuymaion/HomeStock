import SwiftUI

// 位置：房間 → 櫃子（層 × 欄）→ 盒子。
// 同一組畫面有兩種用法：
//   - 管理（「位置」分頁）：pick 為 nil
//   - 選擇位置（登錄物品、移動盒子時）：pick 有值，點一下就選定

struct PickMode {
    var allowBoxes: Bool                 // 可不可以選盒子（移動盒子時不行，盒子不能放進盒子）
    var allowNone: Bool                  // 可不可以選「不指定位置」
    var onPick: (Placement) -> Void
}

/// 跳出來選位置的畫面
struct LocationPickerSheet: View {
    var allowBoxes = true
    var allowNone = true
    var onPick: (Placement) -> Void

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RoomListView(pick: PickMode(allowBoxes: allowBoxes, allowNone: allowNone) { placement in
                onPick(placement)
                dismiss()
            })
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

// MARK: - 房間列表

struct RoomListView: View {
    var pick: PickMode? = nil

    @EnvironmentObject private var store: HomeStore
    @State private var showAdd = false

    var body: some View {
        List {
            if let pick, pick.allowNone {
                Section {
                    Button("不指定位置") {
                        pick.onPick(Placement())
                    }
                }
                .listRowBackground(Theme.card)
            }

            Section {
                if store.rooms.isEmpty {
                    Text("還沒有房間，按右上角 ＋ 新增")
                        .foregroundStyle(Theme.subtext)
                }
                ForEach(store.rooms) { room in
                    NavigationLink {
                        RoomDetailView(roomId: room.id, pick: pick)
                    } label: {
                        HStack {
                            Image(systemName: room.shared ? "house" : "lock.fill")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            Text(room.name)
                            Spacer()
                            Text("\(store.cabinets(in: room.id).count) 個櫃子")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                        }
                    }
                }
            } header: {
                Text("房間")
            } footer: {
                Text("🔒 是私人房間，只有建立者看得到。")
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(pick == nil ? "位置" : "選擇位置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            RoomEditSheet(title: "新增房間", name: "", shared: true, canChangeShared: true) { name, shared in
                store.addRoom(name: name, shared: shared)
            }
        }
    }
}

// MARK: - 單一房間

struct RoomDetailView: View {
    let roomId: String
    var pick: PickMode? = nil

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEditRoom = false
    @State private var showAddCabinet = false
    @State private var showAddBox = false
    @State private var boxName = ""
    @State private var confirmDelete = false

    private var canAddBox: Bool { pick?.allowBoxes ?? true }

    var body: some View {
        if let room = store.room(roomId) {
            content(room)
        } else {
            Text("這個房間已被刪除")
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    private func content(_ room: Room) -> some View {
        List {
            if let pick {
                Section {
                    Button {
                        pick.onPick(Placement(roomId: room.id))
                    } label: {
                        Label("放在這個房間（不放進櫃子）", systemImage: "arrow.down.to.line")
                    }
                }
                .listRowBackground(Theme.card)
            }

            Section {
                let cabinets = store.cabinets(in: room.id)
                if cabinets.isEmpty {
                    Text("還沒有櫃子")
                        .foregroundStyle(Theme.subtext)
                }
                ForEach(cabinets) { cabinet in
                    NavigationLink {
                        CabinetDetailView(cabinetId: cabinet.id, pick: pick)
                    } label: {
                        HStack {
                            Image(systemName: "cabinet")
                                .foregroundStyle(Theme.accent)
                            Text(cabinet.name)
                            Spacer()
                            Text("\(cabinet.rows) 層 × \(cabinet.cols) 欄 · \(store.itemCount(cabinet: cabinet)) 個")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                        }
                    }
                }
                Button {
                    showAddCabinet = true
                } label: {
                    Label("新增櫃子", systemImage: "plus")
                }
            } header: {
                Text("櫃子")
            }
            .listRowBackground(Theme.card)

            let looseBoxes = store.looseBoxes(in: room.id)
            if !looseBoxes.isEmpty || canAddBox {
                Section {
                    ForEach(looseBoxes) { box in
                        BoxRow(box: box, pick: pick)
                    }
                    if canAddBox {
                        Button {
                            boxName = ""
                            showAddBox = true
                        } label: {
                            Label("新增盒子", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("沒放進櫃子的盒子")
                }
                .listRowBackground(Theme.card)
            }

            if pick == nil {
                let looseItems = store.looseItems(in: room.id)
                if !looseItems.isEmpty {
                    Section("直接放在房間的物品") {
                        ForEach(looseItems) { item in
                            NavigationLink {
                                ItemDetailView(itemId: item.id)
                            } label: {
                                ItemRow(item: item)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section("房間設定") {
                    LabeledContent("誰看得到", value: room.shared ? "全家共用" : "只有建立者")
                    LabeledContent("建立者", value: store.memberName(room.ownerUid))
                    Button("編輯房間") { showEditRoom = true }
                    if room.ownerUid == store.uid {
                        Button("刪除房間", role: .destructive) { confirmDelete = true }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedList()
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddCabinet) {
            CabinetEditSheet(title: "新增櫃子", name: "", rows: 3, cols: 1) { name, rows, cols in
                store.addCabinet(roomId: room.id, name: name, rows: rows, cols: cols)
            }
        }
        .sheet(isPresented: $showEditRoom) {
            RoomEditSheet(title: "編輯房間", name: room.name, shared: room.shared,
                          canChangeShared: room.ownerUid == store.uid) { name, shared in
                store.updateRoom(room, name: name, shared: shared)
            }
        }
        .alert("新增盒子", isPresented: $showAddBox) {
            TextField("盒子名稱，例如：電池盒", text: $boxName)
            Button("新增") {
                if !boxName.trimmed.isEmpty {
                    store.addBox(name: boxName.trimmed, at: Placement(roomId: room.id))
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("確定要刪除「\(room.name)」嗎？裡面的櫃子和盒子會一起刪除，物品會變成未指定位置。",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("刪除房間", role: .destructive) {
                dismiss()
                store.deleteRoom(room)
            }
            Button("取消", role: .cancel) {}
        }
    }
}

/// 盒子的一列：管理時點進盒子，選位置時點了就選定
struct BoxRow: View {
    let box: Box
    var pick: PickMode?

    @EnvironmentObject private var store: HomeStore

    var body: some View {
        if let pick {
            if pick.allowBoxes {
                Button {
                    pick.onPick(Placement(boxId: box.id))
                } label: {
                    label
                }
                .foregroundStyle(.primary)
            } else {
                label.foregroundStyle(Theme.subtext)
            }
        } else {
            NavigationLink {
                BoxDetailView(boxId: box.id)
            } label: {
                label
            }
        }
    }

    private var label: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(Theme.warn)
            Text(box.name)
            Spacer()
            Text("\(store.items(inBox: box.id).count) 個")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
    }
}

// MARK: - 櫃子（顯示層 × 欄的格子）

struct CabinetDetailView: View {
    let cabinetId: String
    var pick: PickMode? = nil

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        if let cabinet = store.cabinet(cabinetId) {
            content(cabinet)
        } else {
            Text("這個櫃子已被刪除")
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    private func content(_ cabinet: Cabinet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(pick == nil ? "點一格看裡面放了什麼" : "點一格選擇要放的位置")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)

                VStack(spacing: 8) {
                    ForEach(0..<cabinet.rows, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<cabinet.cols, id: \.self) { col in
                                NavigationLink {
                                    CellView(cabinetId: cabinet.id, row: row, col: col, pick: pick)
                                } label: {
                                    cellLabel(cabinet, row: row, col: col)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.accentSoft, lineWidth: 2)
                )
            }
            .padding()
        }
        .background(Theme.bg)
        .navigationTitle(cabinet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            if pick == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEdit = true
                        } label: {
                            Label("編輯櫃子", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("刪除櫃子", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            CabinetEditSheet(title: "編輯櫃子", name: cabinet.name, rows: cabinet.rows, cols: cabinet.cols) { name, rows, cols in
                store.updateCabinet(cabinet, name: name, rows: rows, cols: cols)
            }
        }
        .confirmationDialog("確定要刪除「\(cabinet.name)」嗎？裡面的盒子和物品會留在同一個房間。",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("刪除櫃子", role: .destructive) {
                dismiss()
                store.deleteCabinet(cabinet)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func cellLabel(_ cabinet: Cabinet, row: Int, col: Int) -> some View {
        let count = store.itemCount(cabinetId: cabinet.id, row: row, col: col)
        let boxCount = store.boxes(in: cabinet.id, row: row, col: col).count
        return VStack(spacing: 4) {
            Text(store.cellName(cabinet, row: row, col: col))
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(count) 個物品")
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
            if boxCount > 0 {
                Label("\(boxCount)", systemImage: "shippingbox.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
    }
}

// MARK: - 櫃子的其中一格

struct CellView: View {
    let cabinetId: String
    let row: Int
    let col: Int
    var pick: PickMode? = nil

    @EnvironmentObject private var store: HomeStore
    @State private var showAddBox = false
    @State private var boxName = ""

    var body: some View {
        if let cabinet = store.cabinet(cabinetId) {
            content(cabinet)
        } else {
            Text("這個櫃子已被刪除")
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    private func content(_ cabinet: Cabinet) -> some View {
        let boxes = store.boxes(in: cabinet.id, row: row, col: col)
        let cellPlacement = Placement(roomId: cabinet.roomId, cabinetId: cabinet.id, row: row, col: col)

        return List {
            if let pick {
                Section {
                    Button {
                        pick.onPick(cellPlacement)
                    } label: {
                        Label("放在這一格", systemImage: "checkmark.circle")
                    }
                }
                .listRowBackground(Theme.card)
            }

            if !boxes.isEmpty || (pick?.allowBoxes ?? true) {
                Section {
                    ForEach(boxes) { box in
                        BoxRow(box: box, pick: pick)
                    }
                    if pick?.allowBoxes ?? true {
                        Button {
                            boxName = ""
                            showAddBox = true
                        } label: {
                            Label("在這一格新增盒子", systemImage: "plus")
                        }
                    }
                } header: {
                    Text(pick == nil ? "盒子" : "或放進這一格的盒子")
                }
                .listRowBackground(Theme.card)
            }

            if pick == nil {
                let items = store.items(in: cabinet.id, row: row, col: col)
                Section("直接放在這一格的物品") {
                    if items.isEmpty {
                        Text("還沒有東西")
                            .foregroundStyle(Theme.subtext)
                    }
                    ForEach(items) { item in
                        NavigationLink {
                            ItemDetailView(itemId: item.id)
                        } label: {
                            ItemRow(item: item)
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedList()
        .navigationTitle("\(cabinet.name) \(store.cellName(cabinet, row: row, col: col))")
        .navigationBarTitleDisplayMode(.inline)
        .alert("新增盒子", isPresented: $showAddBox) {
            TextField("盒子名稱，例如：電池盒", text: $boxName)
            Button("新增") {
                if !boxName.trimmed.isEmpty {
                    store.addBox(name: boxName.trimmed, at: cellPlacement)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 盒子

struct BoxDetailView: View {
    let boxId: String

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var showMove = false
    @State private var confirmDelete = false
    @State private var nameInput = ""

    var body: some View {
        if let box = store.box(boxId) {
            content(box)
        } else {
            Text("這個盒子已被刪除")
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    private func content(_ box: Box) -> some View {
        let items = store.items(inBox: box.id)

        return List {
            Section {
                LabeledContent("位置", value: store.placementText(box.placement) ?? "")
            }
            .listRowBackground(Theme.card)

            Section("盒子裡的物品") {
                if items.isEmpty {
                    Text("還沒有東西")
                        .foregroundStyle(Theme.subtext)
                }
                ForEach(items) { item in
                    NavigationLink {
                        ItemDetailView(itemId: item.id)
                    } label: {
                        ItemRow(item: item)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(box.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        nameInput = box.name
                        showRename = true
                    } label: {
                        Label("重新命名", systemImage: "pencil")
                    }
                    Button {
                        showMove = true
                    } label: {
                        Label("移動盒子", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("刪除盒子", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("重新命名盒子", isPresented: $showRename) {
            TextField("盒子名稱", text: $nameInput)
            Button("儲存") {
                if !nameInput.trimmed.isEmpty {
                    store.renameBox(box, to: nameInput.trimmed)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showMove) {
            LocationPickerSheet(allowBoxes: false, allowNone: false) { placement in
                store.moveBox(box, to: placement)
            }
            .environmentObject(store)
        }
        .confirmationDialog("確定要刪除「\(box.name)」嗎？裡面的物品會留在盒子原本的位置。",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("刪除盒子", role: .destructive) {
                dismiss()
                store.deleteBox(box)
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 新增／編輯用的小視窗

struct RoomEditSheet: View {
    let title: String
    @State var name: String
    @State var shared: Bool
    var canChangeShared: Bool
    var onSave: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("房間名稱，例如：浴室", text: $name)
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("全家共用", isOn: $shared)
                        .disabled(!canChangeShared)
                } footer: {
                    if canChangeShared {
                        Text(shared ? "家人都能看到並編輯這個房間裡的東西。" : "只有你看得到這個房間和裡面的東西。")
                    } else {
                        Text("只有房間的建立者可以切換共用設定。")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(name.trimmed, shared)
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

struct CabinetEditSheet: View {
    let title: String
    @State var name: String
    @State var rows: Int
    @State var cols: Int
    var onSave: (String, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("櫃子名稱，例如：鏡櫃", text: $name)
                }
                .listRowBackground(Theme.card)

                Section {
                    Stepper("層數：\(rows)", value: $rows, in: 1...12)
                    Stepper("欄數：\(cols)", value: $cols, in: 1...8)
                } header: {
                    Text("格數（共 \(rows * cols) 格）")
                } footer: {
                    Text("格子變少時，多出來那幾格的東西會移到最後一層／欄。")
                }
                .listRowBackground(Theme.card)

                Section("預覽") {
                    VStack(spacing: 4) {
                        ForEach(0..<rows, id: \.self) { _ in
                            HStack(spacing: 4) {
                                ForEach(0..<cols, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Theme.cardHigh)
                                        .frame(height: 22)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(name.trimmed, rows, cols)
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
