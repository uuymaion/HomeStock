import SwiftUI

// 網格地圖：每個房間一片網格地板（正上方 2D 視角）。
// - 櫃子、傢俱：佔格子，拖曳移動會對齊格子、不能重疊
// - 牆、門：畫在格線上，不佔格子，可以圍出不是四方形的格局
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
    var displayName: String { kind == .custom ? (name ?? "傢俱") : kind.title }
    var displaySymbol: String { kind == .custom ? (symbol ?? "cube") : kind.symbol }
}

enum FurnitureKind: String, CaseIterable, Identifiable {
    case table, door, bed, chair, custom

    var id: String { rawValue }

    /// ＋ 選單裡可以直接加的內建傢俱（門改成畫在格線上了）
    static let addable: [FurnitureKind] = [.table, .bed, .chair]

    var title: String {
        switch self {
        case .table: return "桌子"
        case .door: return "門（舊）"
        case .bed: return "床"
        case .chair: return "椅子"
        case .custom: return "自訂"
        }
    }

    var symbol: String {
        switch self {
        case .table: return "table.furniture"
        case .door: return "door.left.hand.closed"
        case .bed: return "bed.double"
        case .chair: return "chair"
        case .custom: return "cube"
        }
    }

    var defaultSize: (w: Int, h: Int) {
        switch self {
        case .table: return (2, 1)
        case .door: return (1, 1)
        case .bed: return (2, 3)
        case .chair: return (1, 1)
        case .custom: return (1, 1)
        }
    }
}

/// 自訂傢俱樣板（全家共用），例如「冰箱」
struct FurnitureTemplate: HomeDoc {
    var id: String = ""
    var name: String
    var symbol: String
    var w: Int = 1
    var h: Int = 1
    var createdAt: Date = Date()
}

// MARK: 牆與門（畫在格線上）

enum EdgeKind: String {
    case wall, door

    var title: String { self == .wall ? "牆" : "門" }
}

/// 從格線交叉點 (x, y) 開始，往右（horizontal）或往下延伸 length 格
struct Edge: HomeDoc {
    var id: String = ""
    var roomId: String
    var kindRaw: String
    var x: Int
    var y: Int
    var horizontal: Bool
    var length: Int
    var ownerUid: String
    var shared: Bool
    var createdAt: Date = Date()

    var kind: EdgeKind { EdgeKind(rawValue: kindRaw) ?? .wall }
}

/// 畫牆時的預覽
struct EdgeDraft: Equatable {
    var x: Int
    var y: Int
    var horizontal: Bool
    var length: Int
}

enum MapTool: String, CaseIterable, Identifiable {
    case move = "移動"
    case wall = "畫牆"
    case door = "放門"
    var id: String { rawValue }
}

/// 自訂傢俱可以選的圖示
enum FurnitureIcons {
    static let all: [String] = [
        "refrigerator", "washer", "dryer", "oven", "stove", "microwave",
        "dishwasher", "sink", "toilet", "shower", "bathtub", "sofa",
        "chair.lounge", "chair", "table.furniture", "bed.double", "lamp.desk", "lamp.floor",
        "lamp.table", "fan.ceiling", "fireplace", "air.conditioner.horizontal", "humidifier", "dehumidifier",
        "air.purifier", "heater.vertical", "tv", "desktopcomputer", "printer", "books.vertical",
        "cabinet", "archivebox", "shippingbox", "tshirt", "bicycle", "pianokeys",
        "gamecontroller", "leaf", "pawprint", "trash", "cart", "cube"
    ]
}

// MARK: - 地圖分頁

struct MapView: View {
    @EnvironmentObject private var store: HomeStore

    @State private var selectedRoomId: String?
    @State private var editing = false
    @State private var tool: MapTool = .move
    @State private var openCabinetId: String?
    @State private var editingCabinet: Cabinet?
    @State private var editingFurniture: Furniture?
    @State private var editingEdge: Edge?
    @State private var showAddCabinet = false
    @State private var showRoomSize = false
    @State private var showNewTemplate = false
    @State private var showTemplates = false
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
                    if editing {
                        Picker("工具", selection: $tool) {
                            ForEach(MapTool.allCases) { tool in
                                Text(tool.rawValue).tag(tool)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                    }
                    hint(for: room)
                    RoomGridView(
                        room: room,
                        editing: editing,
                        tool: tool,
                        onOpenCabinet: { openCabinetId = $0.id },
                        onEditCabinet: { editingCabinet = $0 },
                        onEditFurniture: { editingFurniture = $0 },
                        onEditEdge: { editingEdge = $0 }
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
                            tool = .move
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
            .sheet(item: $editingEdge) { edge in
                EdgeSheet(edgeId: edge.id)
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
            .sheet(isPresented: $showNewTemplate) {
                FurnitureTemplateSheet { name, symbol, w, h in
                    // 存成樣板，並在目前的房間放一個
                    guard let id = store.addFurnitureTemplate(name: name, symbol: symbol, w: w, h: h),
                          let room else { return }
                    let template = FurnitureTemplate(id: id, name: name, symbol: symbol, w: w, h: h)
                    if !store.addCustomFurniture(roomId: room.id, template: template) {
                        noSpaceAlert = true
                    }
                }
            }
            .sheet(isPresented: $showTemplates) {
                FurnitureTemplateListSheet()
                    .environmentObject(store)
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

        let text: String
        if !editing {
            text = "點櫃子看裡面放了什麼。要擺放或移動請按左上角「編輯」。"
        } else {
            switch tool {
            case .move: text = "拖曳移動櫃子和傢俱，點一下可以調整大小、旋轉或刪除；點牆或門可以調整長度或刪除。"
            case .wall: text = "從格線的交叉點拖到另一點畫一道牆，會自動拉成直線；點一下已經畫好的牆就會刪掉。"
            case .door: text = "點一下靠近的格線放一扇門，再點一次同一扇門就會刪掉。"
            }
        }

        return VStack(alignment: .leading, spacing: 4) {
            if overlapCount > 0 {
                Label("有 \(overlapCount) 個東西重疊或超出地板（紅框），按「編輯」把它們拖開。",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            }
            Text(text)
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

            Section("傢俱") {
                ForEach(FurnitureKind.addable) { kind in
                    Button {
                        if let room, !store.addFurniture(roomId: room.id, kind: kind) {
                            noSpaceAlert = true
                        }
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }

            Section("自訂傢俱") {
                ForEach(store.furnitureTemplates) { template in
                    Button {
                        if let room, !store.addCustomFurniture(roomId: room.id, template: template) {
                            noSpaceAlert = true
                        }
                    } label: {
                        Label(template.name, systemImage: template.symbol)
                    }
                }
                Button {
                    showNewTemplate = true
                } label: {
                    Label("新增自訂傢俱…", systemImage: "plus")
                }
                if !store.furnitureTemplates.isEmpty {
                    Button {
                        showTemplates = true
                    } label: {
                        Label("管理自訂傢俱…", systemImage: "list.bullet")
                    }
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
    let tool: MapTool
    var onOpenCabinet: (Cabinet) -> Void
    var onEditCabinet: (Cabinet) -> Void
    var onEditFurniture: (Furniture) -> Void
    var onEditEdge: (Edge) -> Void

    @EnvironmentObject private var store: HomeStore
    @State private var drag: DragState?
    @State private var pending: [String: GridRect] = [:]   // 剛放開、等資料庫確認中的位置
    @State private var wallDraft: EdgeDraft?

    struct DragState {
        var id: String
        var rect: GridRect
        var valid: Bool
    }

    private var drawing: Bool { editing && tool != .move }

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
                    ForEach(store.edges(in: room.id)) { edge in
                        edgeView(edge, cell: cell)
                    }
                    if let wallDraft {
                        edgeShape(kind: .wall, horizontal: wallDraft.horizontal, length: wallDraft.length, cell: cell)
                            .opacity(0.6)
                            .allowsHitTesting(false)
                            .position(edgeCenter(x: wallDraft.x, y: wallDraft.y, horizontal: wallDraft.horizontal,
                                                 length: wallDraft.length, cell: cell))
                    }
                    if editing && tool == .wall {
                        Color.white.opacity(0.001)
                            .contentShape(Rectangle())
                            .gesture(wallGesture(cell: cell))
                            .simultaneousGesture(wallTapGesture(cell: cell))
                    }
                    if editing && tool == .door {
                        Color.white.opacity(0.001)
                            .contentShape(Rectangle())
                            .gesture(doorGesture(cell: cell))
                    }
                }
                .frame(width: CGFloat(room.gridW) * cell, height: CGFloat(room.gridH) * cell)
                .coordinateSpace(name: "grid")
                .padding(16)
            }
            .scrollDisabled(drag != nil || drawing)
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
            context.stroke(path, with: .color(Theme.accentSoft.opacity(drawing ? 0.5 : 0.25)), lineWidth: 1)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accentSoft.opacity(0.5), lineWidth: 1))
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
            including: editing && tool == .move ? .all : .subviews
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
                Image(systemName: item.displaySymbol)
                    .font(.caption)
                if rect.w * rect.h > 1 {
                    Text(item.displayName)
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
            including: editing && tool == .move ? .all : .subviews
        )
        .position(center(of: rect, cell: cell))
    }

    // MARK: 牆與門

    private func edgeView(_ edge: Edge, cell: CGFloat) -> some View {
        let length = CGFloat(edge.length) * cell
        let hitThickness: CGFloat = 22   // 點擊範圍比畫出來的線粗，比較好點

        return edgeShape(kind: edge.kind, horizontal: edge.horizontal, length: edge.length, cell: cell)
            .frame(width: edge.horizontal ? length : hitThickness,
                   height: edge.horizontal ? hitThickness : length)
            .contentShape(Rectangle())
            .onTapGesture { onEditEdge(edge) }
            .allowsHitTesting(editing && tool == .move)
            .position(edgeCenter(x: edge.x, y: edge.y, horizontal: edge.horizontal, length: edge.length, cell: cell))
    }

    private func edgeShape(kind: EdgeKind, horizontal: Bool, length: Int, cell: CGFloat) -> some View {
        let full = CGFloat(length) * cell
        return ZStack {
            if kind == .door {
                // 門：先蓋掉底下的牆，再畫一條橘色的線
                Capsule()
                    .fill(Theme.card)
                    .frame(width: horizontal ? full : 10, height: horizontal ? 10 : full)
                Capsule()
                    .fill(Theme.warn)
                    .frame(width: horizontal ? max(full - 8, 4) : 4,
                           height: horizontal ? 4 : max(full - 8, 4))
            } else {
                Capsule()
                    .fill(Theme.subtext)
                    .frame(width: horizontal ? full + 6 : 6, height: horizontal ? 6 : full + 6)
            }
        }
    }

    private func edgeCenter(x: Int, y: Int, horizontal: Bool, length: Int, cell: CGFloat) -> CGPoint {
        let full = CGFloat(length) * cell
        return horizontal
            ? CGPoint(x: CGFloat(x) * cell + full / 2, y: CGFloat(y) * cell)
            : CGPoint(x: CGFloat(x) * cell, y: CGFloat(y) * cell + full / 2)
    }

    /// 畫牆：從手指按下的位置最近的交叉點開始，拉成水平或垂直的直線
    private func wallGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { value in
                wallDraft = wallSegment(from: value.startLocation, to: value.location, cell: cell)
            }
            .onEnded { value in
                if let draft = wallSegment(from: value.startLocation, to: value.location, cell: cell) {
                    store.addEdge(roomId: room.id, kind: .wall, x: draft.x, y: draft.y,
                                  horizontal: draft.horizontal, length: draft.length)
                }
                wallDraft = nil
            }
    }

    private func wallSegment(from start: CGPoint, to end: CGPoint, cell: CGFloat) -> EdgeDraft? {
        let sx = clamp(Int((start.x / cell).rounded()), 0, room.gridW)
        let sy = clamp(Int((start.y / cell).rounded()), 0, room.gridH)
        let dx = end.x / cell - CGFloat(sx)
        let dy = end.y / cell - CGFloat(sy)

        if abs(dx) >= abs(dy) {
            let ex = clamp(sx + Int(dx.rounded()), 0, room.gridW)
            let length = abs(ex - sx)
            guard length > 0 else { return nil }
            return EdgeDraft(x: min(sx, ex), y: sy, horizontal: true, length: length)
        } else {
            let ey = clamp(sy + Int(dy.rounded()), 0, room.gridH)
            let length = abs(ey - sy)
            guard length > 0 else { return nil }
            return EdgeDraft(x: sx, y: min(sy, ey), horizontal: false, length: length)
        }
    }

    /// 放門：找手指點的位置最近的那段格線
    private func doorGesture(cell: CGFloat) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named("grid"))
            .onEnded { value in
                let fx = value.location.x / cell
                let fy = value.location.y / cell
                let toVertical = abs(fx - fx.rounded())
                let toHorizontal = abs(fy - fy.rounded())

                if toVertical <= toHorizontal {
                    let x = clamp(Int(fx.rounded()), 0, room.gridW)
                    let y = clamp(Int(fy.rounded(.down)), 0, room.gridH - 1)
                    toggleDoor(x: x, y: y, horizontal: false)
                } else {
                    let x = clamp(Int(fx.rounded(.down)), 0, room.gridW - 1)
                    let y = clamp(Int(fy.rounded()), 0, room.gridH)
                    toggleDoor(x: x, y: y, horizontal: true)
                }
            }
    }
    /// 畫牆模式下點一下牆，就刪掉那一道牆
    private func wallTapGesture(cell: CGFloat) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named("grid"))
            .onEnded { value in
                let fx = value.location.x / cell
                let fy = value.location.y / cell
                let horizontal = abs(fy - fy.rounded()) < abs(fx - fx.rounded())
                let x = horizontal ? Int(fx.rounded(.down)) : Int(fx.rounded())
                let y = horizontal ? Int(fy.rounded()) : Int(fy.rounded(.down))

                let wall = store.edges(in: room.id).first { edge in
                    guard edge.kind == .wall, edge.horizontal == horizontal else { return false }
                    return horizontal
                        ? (edge.y == y && x >= edge.x && x < edge.x + edge.length)
                        : (edge.x == x && y >= edge.y && y < edge.y + edge.length)
                }
                if let wall {
                    store.deleteEdge(wall)
                }
            }
    }
    /// 那段格線上已經有門就刪掉，沒有就放一扇
    private func toggleDoor(x: Int, y: Int, horizontal: Bool) {
        let existing = store.edges(in: room.id).first { edge in
            guard edge.kind == .door, edge.horizontal == horizontal else { return false }
            return horizontal
                ? (edge.y == y && x >= edge.x && x < edge.x + edge.length)
                : (edge.x == x && y >= edge.y && y < edge.y + edge.length)
        }
        if let existing {
            store.deleteEdge(existing)
        } else {
            store.addEdge(roomId: room.id, kind: .door, x: x, y: y, horizontal: horizontal, length: 1)
        }
    }

    // MARK: 共用

    private func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }

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
    @State private var name = ""
    @State private var symbol = "cube"
    @State private var w = 1
    @State private var h = 1
    @State private var rotated = false
    @State private var errorText: String?

    private var item: Furniture? {
        store.furniture.first { $0.id == furnitureId }
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .custom {
                    Section("名稱") {
                        TextField("傢俱名稱", text: $name)
                    }
                    .listRowBackground(Theme.card)

                    Section("圖示") {
                        IconPicker(selection: $symbol)
                    }
                    .listRowBackground(Theme.card)
                } else {
                    Section("種類") {
                        Picker("種類", selection: $kind) {
                            ForEach(FurnitureKind.addable) { kind in
                                Label(kind.title, systemImage: kind.symbol).tag(kind)
                            }
                            if item?.kind == .door {
                                Label(FurnitureKind.door.title, systemImage: FurnitureKind.door.symbol)
                                    .tag(FurnitureKind.door)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }

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
                        if let item { store.deleteFurniture(item) }
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
                        .disabled(kind == .custom && name.trimmed.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func load() {
        guard !loaded, let item else { return }
        loaded = true
        kind = item.kind
        name = item.name ?? ""
        symbol = item.symbol ?? "cube"
        w = item.w
        h = item.h
        rotated = item.rotated
    }

    private func save() {
        guard let item, let room = store.room(item.roomId) else {
            dismiss()
            return
        }
        var updated = item
        updated.kindRaw = kind.rawValue
        if kind == .custom {
            updated.name = name.trimmed
            updated.symbol = symbol
        }
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

// MARK: - 編輯牆／門

struct EdgeSheet: View {
    let edgeId: String

    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var length = 1
    @State private var loaded = false

    private var edge: Edge? {
        store.edges.first { $0.id == edgeId }
    }

    /// 最長能延伸到地板邊緣
    private var maxLength: Int {
        guard let edge, let room = store.room(edge.roomId) else { return 1 }
        return max(1, edge.horizontal ? room.gridW - edge.x : room.gridH - edge.y)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let edge {
                    Section {
                        LabeledContent("種類", value: edge.kind.title)
                        LabeledContent("方向", value: edge.horizontal ? "橫向" : "直向")
                        Stepper("長度：\(length) 格", value: $length, in: 1...maxLength)
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Button("刪除這\(edge.kind == .door ? "扇門" : "道牆")", role: .destructive) {
                            store.deleteEdge(edge)
                            dismiss()
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .themedList()
            .navigationTitle("編輯\(edge?.kind.title ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        if var updated = edge {
                            updated.length = min(length, maxLength)
                            store.updateEdge(updated)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded, let edge else { return }
                loaded = true
                length = edge.length
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

// MARK: - 自訂傢俱樣板

/// 圖示選擇格
struct IconPicker: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(FurnitureIcons.all, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selection == icon ? Color.white : Theme.subtext)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == icon ? Theme.accent : Theme.cardHigh)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 新增自訂傢俱樣板
struct FurnitureTemplateSheet: View {
    var onSave: (String, String, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "refrigerator"
    @State private var w = 1
    @State private var h = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("名稱") {
                    TextField("例如：冰箱", text: $name)
                }
                .listRowBackground(Theme.card)

                Section("圖示") {
                    IconPicker(selection: $symbol)
                }
                .listRowBackground(Theme.card)

                Section {
                    Stepper("寬：\(w) 格", value: $w, in: 1...8)
                    Stepper("深：\(h) 格", value: $h, in: 1...8)
                } header: {
                    Text("預設大小")
                } footer: {
                    Text("存成樣板後，全家都能從 ＋ 選單直接加入；放好之後還是可以各自調整大小。")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("新增自訂傢俱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(name.trimmed, symbol, w, h)
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

/// 管理自訂傢俱樣板（刪除樣板不會刪掉已經放好的傢俱）
struct FurnitureTemplateListSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.furnitureTemplates) { template in
                        HStack {
                            Image(systemName: template.symbol)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            Text(template.name)
                            Spacer()
                            Text("\(template.w) × \(template.h) 格")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { store.furnitureTemplates[$0] }
                        for template in targets {
                            store.deleteFurnitureTemplate(template)
                        }
                    }
                } footer: {
                    Text("左滑可以刪除樣板。已經放在地圖上的傢俱不會被刪掉。")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("自訂傢俱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                FurnitureTemplateSheet { name, symbol, w, h in
                    _ = store.addFurnitureTemplate(name: name, symbol: symbol, w: w, h: h)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
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

    /// 不能縮到比櫃子、傢俱、牆、門還小
    private var minimum: (w: Int, h: Int) {
        let objects = store.minimumSize(of: room)
        let edges = store.edgeExtent(of: room)
        return (max(objects.w, edges.w), max(objects.h, edges.h))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("寬：\(w) 格", value: $w, in: minimum.w...30)
                    Stepper("深：\(h) 格", value: $h, in: minimum.h...30)
                } header: {
                    Text("「\(room.name)」的地板")
                } footer: {
                    Text("預設 10 × 8 格。不能縮到比目前擺放的東西還小。不是四方形的房間，可以用「畫牆」把實際的形狀圍出來。")
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
