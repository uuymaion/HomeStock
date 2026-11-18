import SwiftUI

// 網格地圖：每個房間一片網格地板（正上方 2D 視角）。
// 編輯模式可以新增櫃子和傢俱、拖曳移動（會對齊格子、不能重疊）、點一下調整大小或旋轉。
// 一般模式點櫃子會打開櫃子，看每一格放了什麼。物品記在櫃子的格子裡，所以搬櫃子時東西會跟著走。

// MARK: - 共用型別

struct GridRect: Equatable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    func intersects(_ other: GridRect) -> Bool {
        x < other.x + other.w && other.x < x + w &&
        y < other.y + other.h && other.y < y + h
    }
}

extension Cabinet {
    /// 在地板上實際佔的格子（旋轉時寬高對調）
    var rect: GridRect { GridRect(x: x, y: y, w: rotated ? h : w, h: rotated ? w : h) }
}

extension Furniture {
    var rect: GridRect { GridRect(x: x, y: y, w: rotated ? h : w, h: rotated ? w : h) }
    var kind: FurnitureKind { FurnitureKind(rawValue: kindRaw) ?? .table }
}

enum FurnitureKind: String, CaseIterable, Identifiable {
    case table, door, bed, chair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: return "桌子"
        case .door: return "門"
        case .bed: return "床"
        case .chair: return "椅子"
        }
    }

    var symbol: String {
        switch self {
        case .table: return "table.furniture"
        case .door: return "door.left.hand.closed"
        case .bed: return "bed.double"
        case .chair: return "chair"
        }
    }

    var defaultSize: (w: Int, h: Int) {
        switch self {
        case .table: return (2, 1)
        case .door: return (1, 1)
        case .bed: return (2, 3)
        case .chair: return (1, 1)
        }
    }
}

// MARK: - 地圖分頁

struct MapView: View {
    @EnvironmentObject private var store: HomeStore

    @State private var selectedRoomId: String?
    @State private var editing = false
    @State private var openCabinetId: String?
    @State private var editingCabinet: Cabinet?
    @State private var editingFurniture: Furniture?
    @State private var showAddCabinet = false
    @State private var showRoomSize = false
    @State private var noSpaceAlert = false

    private var room: Room? {
        store.room(selectedRoomId) ?? store.rooms.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.rooms.isEmpty {
                    emptyState
                } else if let room {
                    roomBar(current: room)
                    hint(for: room)
                    RoomGridView(
                        room: room,
                        editing: editing,
                        onOpenCabinet: { openCabinetId = $0.id },
                        onEditCabinet: { editingCabinet = $0 },
                        onEditFurniture: { editingFurniture = $0 }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("地圖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                if room != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(editing ? "完成" : "編輯") {
                            editing.toggle()
                        }
                    }
                    if editing {
                        ToolbarItem(placement: .topBarTrailing) {
                            addMenu
                        }
                    }
                }
            }
            .navigationDestination(item: $openCabinetId) { id in
                CabinetDetailView(cabinetId: id)
            }
            .sheet(item: $editingCabinet) { cabinet in
                CabinetLayoutSheet(cabinetId: cabinet.id)
                    .environmentObject(store)
            }
            .sheet(item: $editingFurniture) { item in
                FurnitureSheet(furnitureId: item.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddCabinet) {
                CabinetEditSheet(title: "新增櫃子", name: "", rows: 3, cols: 1) { name, rows, cols in
                    if let room {
                        store.addCabinet(roomId: room.id, name: name, rows: rows, cols: cols)
                    }
                }
            }
            .sheet(isPresented: $showRoomSize) {
                if let room {
                    RoomSizeSheet(room: room)
                        .environmentObject(store)
                }
            }
            .alert("房間裡沒有空位了", isPresented: $noSpaceAlert) {
                Button("好") {}
            } message: {
                Text("先把地板調大，或把其他東西移開。")
            }
        }
    }

    // MARK: - 子畫面

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accentSoft)
            Text("還沒有房間")
                .foregroundStyle(Theme.subtext)
            Text("到「位置」分頁新增房間後，就能在這裡擺放櫃子和傢俱。")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func roomBar(current: Room) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.rooms) { room in
                    let selected = room.id == current.id
                    Button {
                        selectedRoomId = room.id
                    } label: {
                        HStack(spacing: 4) {
                            if !room.shared {
                                Image(systemName: "lock.fill").font(.caption2)
                            }
                            Text(room.name)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? Color.white : Theme.subtext)
                        .background(Capsule().fill(selected ? Theme.accent : Theme.card))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func hint(for room: Room) -> some View {
        let overlapCount =
            store.cabinets(in: room.id).filter { !store.canPlace($0.rect, in: room, excluding: $0.id) }.count +
            store.furniture(in: room.id).filter { !store.canPlace($0.rect, in: room, excluding: $0.id) }.count

        return VStack(alignment: .leading, spacing: 4) {
            if overlapCount > 0 {
                Label("有 \(overlapCount) 個東西重疊或超出地板（紅框），按「編輯」把它們拖開。",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            }
            Text(editing
                 ? "拖曳可以移動，點一下可以調整大小、旋轉或刪除。地板 \(room.gridW) × \(room.gridH) 格。"
                 : "點櫃子看裡面放了什麼。要擺放或移動請按左上角「編輯」。")
                .foregroundStyle(Theme.subtext)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var addMenu: some View {
        Menu {
            Button {
                showAddCabinet = true
            } label: {
                Label("櫃子", systemImage: "cabinet")
            }
            ForEach(FurnitureKind.allCases) { kind in
                Button {
                    if let room, !store.addFurniture(roomId: room.id, kind: kind) {
                        noSpaceAlert = true
                    }
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
            Divider()
            Button {
                showRoomSize = true
            } label: {
                Label("地板大小", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
}

// MARK: - 網格地板

struct RoomGridView: View {
    let room: Room
    let editing: Bool
    var onOpenCabinet: (Cabinet) -> Void
    var onEditCabinet: (Cabinet) -> Void
    var onEditFurniture: (Furniture) -> Void

    @EnvironmentObject private var store: HomeStore
    @State private var drag: DragState?
    @State private var pending: [String: GridRect] = [:]   // 剛放開、等資料庫確認中的位置

    struct DragState {
        var id: String
        var rect: GridRect
        var valid: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let cell = max(28, floor((geo.size.width - 32) / CGFloat(max(room.gridW, 1))))
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    floorView(cell: cell)
                    ForEach(store.furniture(in: room.id)) { item in
                        furnitureView(item, cell: cell)
                    }
                    ForEach(store.cabinets(in: room.id)) { cabinet in
                        cabinetView(cabinet, cell: cell)
                    }
                }
                .frame(width: CGFloat(room.gridW) * cell, height: CGFloat(room.gridH) * cell)
                .coordinateSpace(name: "grid")
                .padding(16)
            }
            .scrollDisabled(drag != nil)
        }
    }

    // MARK: 地板格線

    private func floorView(cell: CGFloat) -> some View {
        Canvas { context, size in
            var path = Path()
            for i in 0...room.gridW {
                let x = CGFloat(i) * cell
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for j in 0...room.gridH {
                let y = CGFloat(j) * cell
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Theme.accentSoft.opacity(0.25)), lineWidth: 1)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accentSoft, lineWidth: 2))
    }

    // MARK: 櫃子

    private func cabinetView(_ cabinet: Cabinet, cell: CGFloat) -> some View {
        let dragging = drag?.id == cabinet.id
        let rect = dragging ? (drag?.rect ?? cabinet.rect) : (pending[cabinet.id] ?? cabinet.rect)
        let invalid = dragging
            ? !(drag?.valid ?? true)
            : !store.canPlace(cabinet.rect, in: room, excluding: cabinet.id)

        return box(rect: rect, cell: cell,
                   fill: Theme.accent.opacity(dragging ? 0.6 : 0.85),
                   border: invalid ? Theme.danger : Color.white.opacity(editing ? 0.8 : 0.3)) {
            VStack(spacing: 2) {
                Text(cabinet.name)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(store.itemCount(cabinet: cabinet)) 個")
                    .font(.caption2)
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(.white)
            .padding(2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editing { onEditCabinet(cabinet) } else { onOpenCabinet(cabinet) }
        }
        .gesture(
            dragGesture(id: cabinet.id, original: cabinet.rect, cell: cell) { newRect in
                store.updateCabinetLayout(cabinet, x: newRect.x, y: newRect.y,
                                          w: cabinet.w, h: cabinet.h, rotated: cabinet.rotated)
            },
            including: editing ? .all : .subviews
        )
        .position(center(of: rect, cell: cell))
    }

    // MARK: 傢俱

    private func furnitureView(_ item: Furniture, cell: CGFloat) -> some View {
        let dragging = drag?.id == item.id
        let rect = dragging ? (drag?.rect ?? item.rect) : (pending[item.id] ?? item.rect)
        let invalid = dragging
            ? !(drag?.valid ?? true)
            : !store.canPlace(item.rect, in: room, excluding: item.id)

        return box(rect: rect, cell: cell,
                   fill: Theme.cardHigh.opacity(dragging ? 0.7 : 1),
                   border: invalid ? Theme.danger : Theme.subtext.opacity(editing ? 0.7 : 0.3)) {
            VStack(spacing: 2) {
                Image(systemName: item.kind.symbol)
                    .font(.caption)
                if rect.w * rect.h > 1 {
                    Text(item.kind.title)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(Theme.subtext)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editing { onEditFurniture(item) }
        }
        .gesture(
            dragGesture(id: item.id, original: item.rect, cell: cell) { newRect in
                var moved = item
                moved.x = newRect.x
                moved.y = newRect.y
                store.updateFurniture(moved)
            },
            including: editing ? .all : .subviews
        )
        .position(center(of: rect, cell: cell))
    }

    // MARK: 共用

    private func box<Content: View>(rect: GridRect, cell: CGFloat, fill: Color, border: Color,
                                    @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 2))
            .overlay(content())
            .frame(width: CGFloat(rect.w) * cell - 4, height: CGFloat(rect.h) * cell - 4)
    }

    private func center(of rect: GridRect, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(rect.x) + CGFloat(rect.w) / 2) * cell,
                y: (CGFloat(rect.y) + CGFloat(rect.h) / 2) * cell)
    }

    /// 拖曳時對齊格子；放開時位置合法才存檔，不合法就彈回原位
    private func dragGesture(id: String, original: GridRect, cell: CGFloat,
                             commit: @escaping (GridRect) -> Void) -> some Gesture {
        DragGesture(coordinateSpace: .named("grid"))
            .onChanged { value in
                var moved = original
                moved.x = original.x + Int((value.translation.width / cell).rounded())
                moved.y = original.y + Int((value.translation.height / cell).rounded())
                drag = DragState(id: id, rect: moved, valid: store.canPlace(moved, in: room, excluding: id))
            }
            .onEnded { _ in
                if let current = drag, current.id == id, current.valid, current.rect != original {
                    pending[id] = current.rect
                    commit(current.rect)
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        pending[id] = nil
                    }
                }
                drag = nil
            }
    }
}

// MARK: - 編輯櫃子（名稱、格數、大小、旋轉）

struct CabinetLayoutSheet: View {
    let cabinetId: String

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var name = ""
    @State private var rows = 3
    @State private var cols = 1
    @State private var w = 2
    @State private var h = 1
    @State private var rotated = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名稱") {
                    TextField("櫃子名稱", text: $name)
                }
                .listRowBackground(Theme.card)

                Section("格數（共 \(rows * cols) 格）") {
                    Stepper("層數：\(rows)", value: $rows, in: 1...12)
                    Stepper("欄數：\(cols)", value: $cols, in: 1...8)
                }
                .listRowBackground(Theme.card)

                Section {
                    Stepper("寬：\(w) 格", value: $w, in: 1...8)
                    Stepper("深：\(h) 格", value: $h, in: 1...8)
                    Toggle("旋轉 90°", isOn: $rotated)
                } header: {
                    Text("在地板上的大小")
                } footer: {
                    Text("如果原本的位置放不下，會自動移到其他空位。")
                }
                .listRowBackground(Theme.card)

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button("刪除櫃子", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("刪除後，裡面的盒子和物品會留在同一個房間。")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("編輯櫃子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save)
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("確定要刪除這個櫃子嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let cabinet = store.cabinet(cabinetId) { store.deleteCabinet(cabinet) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func load() {
        guard !loaded, let cabinet = store.cabinet(cabinetId) else { return }
        loaded = true
        name = cabinet.name
        rows = cabinet.rows
        cols = cabinet.cols
        w = cabinet.w
        h = cabinet.h
        rotated = cabinet.rotated
    }

    private func save() {
        guard let cabinet = store.cabinet(cabinetId), let room = store.room(cabinet.roomId) else {
            dismiss()
            return
        }
        var updated = cabinet
        updated.w = w
        updated.h = h
        updated.rotated = rotated

        if !store.canPlace(updated.rect, in: room, excluding: cabinet.id) {
            let size = updated.rect
            guard let spot = store.freeSpot(in: room, w: size.w, h: size.h, excluding: cabinet.id) else {
                errorText = "這個大小放不下。先把地板調大，或把其他東西移開。"
                return
            }
            updated.x = spot.x
            updated.y = spot.y
        }
        store.updateCabinet(updated, name: name.trimmed, rows: rows, cols: cols)
        dismiss()
    }
}

// MARK: - 編輯傢俱

struct FurnitureSheet: View {
    let furnitureId: String

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var kind: FurnitureKind = .table
    @State private var w = 1
    @State private var h = 1
    @State private var rotated = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("種類") {
                    Picker("種類", selection: $kind) {
                        ForEach(FurnitureKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section("大小") {
                    Stepper("寬：\(w) 格", value: $w, in: 1...8)
                    Stepper("深：\(h) 格", value: $h, in: 1...8)
                    Toggle("旋轉 90°", isOn: $rotated)
                }
                .listRowBackground(Theme.card)

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button("刪除", role: .destructive) {
                        if let item = store.furniture.first(where: { $0.id == furnitureId }) {
                            store.deleteFurniture(item)
                        }
                        dismiss()
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("編輯傢俱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func load() {
        guard !loaded, let item = store.furniture.first(where: { $0.id == furnitureId }) else { return }
        loaded = true
        kind = item.kind
        w = item.w
        h = item.h
        rotated = item.rotated
    }

    private func save() {
        guard let item = store.furniture.first(where: { $0.id == furnitureId }),
              let room = store.room(item.roomId) else {
            dismiss()
            return
        }
        var updated = item
        updated.kindRaw = kind.rawValue
        updated.w = w
        updated.h = h
        updated.rotated = rotated

        if !store.canPlace(updated.rect, in: room, excluding: item.id) {
            let size = updated.rect
            guard let spot = store.freeSpot(in: room, w: size.w, h: size.h, excluding: item.id) else {
                errorText = "這個大小放不下。先把地板調大，或把其他東西移開。"
                return
            }
            updated.x = spot.x
            updated.y = spot.y
        }
        store.updateFurniture(updated)
        dismiss()
    }
}

// MARK: - 地板大小

struct RoomSizeSheet: View {
    let room: Room

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var w = 10
    @State private var h = 8
    @State private var loaded = false

    var body: some View {
        let minimum = store.minimumSize(of: room)

        NavigationStack {
            Form {
                Section {
                    Stepper("寬：\(w) 格", value: $w, in: minimum.w...30)
                    Stepper("深：\(h) 格", value: $h, in: minimum.h...30)
                } header: {
                    Text("「\(room.name)」的地板")
                } footer: {
                    Text("預設 10 × 8 格。不能縮到比目前擺放的東西還小。")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("地板大小")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        store.updateRoomSize(room, w: w, h: h)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                w = max(room.gridW, minimum.w)
                h = max(room.gridH, minimum.h)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
