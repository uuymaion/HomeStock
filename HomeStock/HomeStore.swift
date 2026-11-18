import Foundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

enum HomeError: LocalizedError {
    case notSignedIn
    case wrongCodeOrPassword
    case codeUnavailable
    case notOwner

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "尚未登入，請確認網路後重新開啟 App"
        case .wrongCodeOrPassword: return "家庭代碼或密碼錯誤"
        case .codeUnavailable: return "無法產生家庭代碼，請再試一次"
        case .notOwner: return "只有家庭建立者可以做這件事"
        }
    }
}

/// 所有資料的讀寫都經過這裡。
/// 畫面只讀取這裡的陣列；寫入後 Firebase 會立刻更新陣列（沒網路也會先存在手機，連線後同步）。
@MainActor
final class HomeStore: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var startError: String?
    @Published private(set) var uid: String?
    @Published private(set) var familyId: String?
    @Published private(set) var family: Family?
    @Published private(set) var members: [Member] = []
    @Published private(set) var tags: [ItemTag] = []
    @Published private(set) var rooms: [Room] = []
    @Published private(set) var cabinets: [Cabinet] = []
    @Published private(set) var boxes: [Box] = []
    @Published private(set) var furniture: [Furniture] = []
    @Published private(set) var items: [Item] = [] {
        didSet { NotificationManager.shared.rescheduleAll(items: items) }
    }
    /// 剛建立家庭時用來顯示代碼
    @Published var newFamilyCode: String?

    private var listeners: [ListenerRegistration] = []
    private var parts: [String: Any] = [:]
    private var db: Firestore { Firestore.firestore() }

    var isFamilyOwner: Bool {
        guard let uid, let family else { return false }
        return family.ownerUid == uid
    }

    // MARK: - 啟動

    func start() async {
        startError = nil
        if let user = Auth.auth().currentUser {
            uid = user.uid
        } else {
            do {
                let result = try await Auth.auth().signInAnonymously()
                uid = result.user.uid
            } catch {
                startError = "無法連線：\(error.localizedDescription)"
                return
            }
        }
        if familyId == nil, let saved = UserDefaults.standard.string(forKey: "familyId") {
            familyId = saved
            attach()
        }
        ready = true
    }

    // MARK: - 家庭

    func createFamily(familyName: String, nickname: String, password: String) async throws -> String {
        guard let uid else { throw HomeError.notSignedIn }

        for _ in 0..<5 {
            let code = Self.randomCode()
            let key = Self.joinKey(code: code, password: password)
            let familyRef = db.collection("families").document(code)
            let family = Family(name: familyName, ownerUid: uid, joinKey: key, createdAt: Date())

            do {
                let data = try encode(family)
                try await familyRef.setData(data)
            } catch {
                // 這個代碼已經有人用了，換一個
                if isPermissionDenied(error) { continue }
                throw error
            }

            try await familyRef.collection("keys").document(key).setData(["createdAt": Date()])
            let memberData = try encode(Member(name: nickname, joinKey: key))
            try await familyRef.collection("members").document(uid).setData(memberData)

            useFamily(code)
            for name in ["洗漱用品", "衛生用品", "電子用品"] {
                addTag(name: name, kind: .category)
            }
            newFamilyCode = code
            return code
        }
        throw HomeError.codeUnavailable
    }

    func joinFamily(code rawCode: String, password: String, nickname: String) async throws {
        guard let uid else { throw HomeError.notSignedIn }
        let code = rawCode.trimmed.uppercased()
        let key = Self.joinKey(code: code, password: password)
        let familyRef = db.collection("families").document(code)

        do {
            let memberData = try encode(Member(name: nickname, joinKey: key))
            try await familyRef.collection("members").document(uid).setData(memberData)
        } catch {
            if isPermissionDenied(error) { throw HomeError.wrongCodeOrPassword }
            throw error
        }
        useFamily(code)
    }

    func leaveFamily() {
        let oldFamily = familyId
        detach()
        if let oldFamily, let uid {
            db.collection("families").document(oldFamily).collection("members").document(uid).delete()
        }
        familyId = nil
        UserDefaults.standard.removeObject(forKey: "familyId")
    }

    func removeMember(_ member: Member) {
        guard isFamilyOwner, member.id != uid, let ref = self.ref("members", member.id) else { return }
        ref.delete()
    }

    func changePassword(_ newPassword: String) async throws {
        guard let familyId, let family, isFamilyOwner else { throw HomeError.notOwner }
        let familyRef = db.collection("families").document(familyId)
        let newKey = Self.joinKey(code: familyId, password: newPassword)
        guard newKey != family.joinKey else { return }

        try await familyRef.collection("keys").document(newKey).setData(["createdAt": Date()])
        try await familyRef.collection("keys").document(family.joinKey).delete()
        try await familyRef.updateData(["joinKey": newKey])
    }

    private func useFamily(_ code: String) {
        familyId = code
        UserDefaults.standard.set(code, forKey: "familyId")
        attach()
    }

    // MARK: - 監聽雲端資料

    private func attach() {
        detach()
        guard let familyId else { return }
        let familyRef = db.collection("families").document(familyId)

        let familyListener = familyRef.addSnapshotListener { [weak self] snap, _ in
            let value = try? snap?.data(as: Family.self)
            MainActor.assumeIsolated { self?.family = value }
        }
        listeners.append(familyListener)

        listenAll(familyRef.collection("members"), Member.self) { [weak self] in self?.members = $0 }
        listenAll(familyRef.collection("tags"), ItemTag.self) { [weak self] in self?.tags = $0 }
        listenVisible(familyRef.collection("rooms"), "rooms", Room.self) { [weak self] in self?.rooms = $0 }
        listenVisible(familyRef.collection("cabinets"), "cabinets", Cabinet.self) { [weak self] in self?.cabinets = $0 }
        listenVisible(familyRef.collection("boxes"), "boxes", Box.self) { [weak self] in self?.boxes = $0 }
        listenVisible(familyRef.collection("furniture"), "furniture", Furniture.self) { [weak self] in self?.furniture = $0 }
        listenVisible(familyRef.collection("items"), "items", Item.self) { [weak self] in self?.items = $0 }
    }

    private func detach() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        parts.removeAll()
        family = nil
        members = []
        tags = []
        rooms = []
        cabinets = []
        boxes = []
        furniture = []
        items = []
    }

    private func listenAll<T: HomeDoc>(_ query: Query, _ type: T.Type, assign: @escaping @MainActor ([T]) -> Void) {
        let listener = query.addSnapshotListener { snap, _ in
            guard let snap else { return }
            let values = Self.decode(snap, T.self).sorted { $0.createdAt < $1.createdAt }
            MainActor.assumeIsolated { assign(values) }
        }
        listeners.append(listener)
    }

    /// 只讀取「全家共用」和「自己的」兩種資料，再合併起來
    private func listenVisible<T: HomeDoc>(_ collection: CollectionReference, _ key: String, _ type: T.Type,
                                           assign: @escaping @MainActor ([T]) -> Void) {
        guard let uid else { return }
        let queries: [Query] = [
            collection.whereField("shared", isEqualTo: true),
            collection.whereField("ownerUid", isEqualTo: uid)
        ]
        for (index, query) in queries.enumerated() {
            let partKey = "\(key).\(index)"
            let listener = query.addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                var dict: [String: T] = [:]
                for value in Self.decode(snap, T.self) {
                    dict[value.id] = value
                }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.parts[partKey] = dict
                    let first = self.parts["\(key).0"] as? [String: T] ?? [:]
                    let second = self.parts["\(key).1"] as? [String: T] ?? [:]
                    let merged = first.merging(second) { a, _ in a }
                    assign(merged.values.sorted { $0.createdAt < $1.createdAt })
                }
            }
            listeners.append(listener)
        }
    }

    nonisolated private static func decode<T: HomeDoc>(_ snap: QuerySnapshot, _ type: T.Type) -> [T] {
        snap.documents.compactMap { doc in
            guard var value = try? doc.data(as: T.self) else { return nil }
            value.id = doc.documentID
            return value
        }
    }

    // MARK: - 查詢

    func tag(_ id: String) -> ItemTag? { tags.first { $0.id == id } }

    func room(_ id: String?) -> Room? {
        guard let id else { return nil }
        return rooms.first { $0.id == id }
    }

    func cabinet(_ id: String?) -> Cabinet? {
        guard let id else { return nil }
        return cabinets.first { $0.id == id }
    }

    func box(_ id: String?) -> Box? {
        guard let id else { return nil }
        return boxes.first { $0.id == id }
    }

    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    func memberName(_ uid: String) -> String {
        members.first { $0.id == uid }?.name ?? "家人"
    }

    func category(of item: Item) -> ItemTag? {
        item.tagIds.compactMap { tag($0) }.first { $0.kind == .category }
    }

    func subTags(of item: Item) -> [ItemTag] {
        item.tagIds.compactMap { tag($0) }.filter { $0.kind == .sub }
    }

    func brands(of item: Item) -> [ItemTag] {
        item.tagIds.compactMap { tag($0) }.filter { $0.kind == .brand }
    }

    func cabinets(in roomId: String) -> [Cabinet] {
        cabinets.filter { $0.roomId == roomId }
    }

    func looseBoxes(in roomId: String) -> [Box] {
        boxes.filter { $0.roomId == roomId && $0.cabinetId == nil }
    }

    func boxes(in cabinetId: String, row: Int, col: Int) -> [Box] {
        boxes.filter { $0.cabinetId == cabinetId && $0.row == row && $0.col == col }
    }

    func looseItems(in roomId: String) -> [Item] {
        items.filter { $0.roomId == roomId && $0.cabinetId == nil && $0.boxId == nil }
    }

    func items(in cabinetId: String, row: Int, col: Int) -> [Item] {
        items.filter { $0.boxId == nil && $0.cabinetId == cabinetId && $0.row == row && $0.col == col }
    }

    func items(inBox boxId: String) -> [Item] {
        items.filter { $0.boxId == boxId }
    }

    func itemCount(cabinet: Cabinet) -> Int {
        items.filter { item in
            if let box = self.box(item.boxId) { return box.cabinetId == cabinet.id }
            return item.cabinetId == cabinet.id
        }.count
    }

    func itemCount(cabinetId: String, row: Int, col: Int) -> Int {
        let boxIds = Set(boxes(in: cabinetId, row: row, col: col).map(\.id))
        return items(in: cabinetId, row: row, col: col).count
            + items.filter { item in item.boxId.map { boxIds.contains($0) } ?? false }.count
    }

    func cellName(_ cabinet: Cabinet, row: Int, col: Int) -> String {
        cabinet.cols > 1 ? "第 \(row + 1) 層第 \(col + 1) 欄" : "第 \(row + 1) 層"
    }

    /// 例如「浴室 › 鏡櫃 › 第 2 層 › 盒子：棉花棒」
    func placementText(_ p: Placement) -> String? {
        if let box = self.box(p.boxId) {
            if let base = placementText(box.placement) {
                return "\(base) › 盒子：\(box.name)"
            }
            return "盒子：\(box.name)"
        }
        guard let room = self.room(p.roomId) else { return nil }
        var parts = [room.name]
        if let cabinet = self.cabinet(p.cabinetId) {
            parts.append(cabinet.name)
            if let row = p.row, let col = p.col {
                parts.append(cellName(cabinet, row: row, col: col))
            }
        }
        return parts.joined(separator: " › ")
    }

    /// 這個位置所在的房間（放在盒子裡就看盒子的房間）
    func roomOf(_ p: Placement) -> Room? {
        if let box = self.box(p.boxId) { return room(box.roomId) }
        return room(p.roomId)
    }

    // MARK: - 寫入共用工具

    private func ref(_ collection: String, _ id: String) -> DocumentReference? {
        guard let familyId, !id.isEmpty else { return nil }
        return db.collection("families").document(familyId).collection(collection).document(id)
    }

    private func newId(_ collection: String) -> String? {
        guard let familyId else { return nil }
        return db.collection("families").document(familyId).collection(collection).document().documentID
    }

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        try Firestore.Encoder().encode(value)
    }

    private func put<T: HomeDoc>(_ value: T, in collection: String, batch: WriteBatch? = nil) {
        guard let ref = self.ref(collection, value.id), let data = try? encode(value) else { return }
        if let batch {
            batch.setData(data, forDocument: ref)
        } else {
            ref.setData(data)
        }
    }

    private func remove(_ collection: String, _ id: String, batch: WriteBatch? = nil) {
        guard let ref = self.ref(collection, id) else { return }
        if let batch {
            batch.deleteDocument(ref)
        } else {
            ref.delete()
        }
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.Code.permissionDenied.rawValue
    }

    nonisolated static func joinKey(code: String, password: String) -> String {
        let data = Data("homestock|\(code)|\(password)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func randomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    // MARK: - 標籤

    @discardableResult
    func addTag(name: String, kind: TagKind) -> String? {
        if let existing = tags.first(where: { $0.kindRaw == kind.rawValue && $0.name == name }) {
            return existing.id
        }
        guard let id = newId("tags") else { return nil }
        put(ItemTag(id: id, name: name, kindRaw: kind.rawValue), in: "tags")
        return id
    }

    func deleteTag(_ tag: ItemTag) {
        remove("tags", tag.id)
    }

    // MARK: - 房間

    func addRoom(name: String, shared: Bool) {
        guard let uid, let id = newId("rooms") else { return }
        put(Room(id: id, name: name, ownerUid: uid, shared: shared), in: "rooms")
    }

    /// 改名與切換共用。切換共用時，房間裡的櫃子、盒子、物品會一起切換。
    func updateRoom(_ room: Room, name: String, shared: Bool) {
        var updated = room
        updated.name = name
        updated.shared = shared
        let batch = db.batch()
        put(updated, in: "rooms", batch: batch)

        if shared != room.shared {
            for var cabinet in cabinets where cabinet.roomId == room.id {
                cabinet.shared = shared
                cabinet.ownerUid = room.ownerUid
                put(cabinet, in: "cabinets", batch: batch)
            }
            for var box in boxes where box.roomId == room.id {
                box.shared = shared
                box.ownerUid = room.ownerUid
                put(box, in: "boxes", batch: batch)
            }
            for var item in items where item.roomId == room.id {
                item.shared = shared
                item.ownerUid = room.ownerUid
                put(item, in: "items", batch: batch)
            }
            for var item in furniture where item.roomId == room.id {
                item.shared = shared
                item.ownerUid = room.ownerUid
                put(item, in: "furniture", batch: batch)
            }
        }
        batch.commit()
    }

    /// 刪除房間：櫃子和盒子一起刪掉，物品保留但變成未指定位置
    func deleteRoom(_ room: Room) {
        let batch = db.batch()
        remove("rooms", room.id, batch: batch)
        for cabinet in cabinets where cabinet.roomId == room.id {
            remove("cabinets", cabinet.id, batch: batch)
        }
        for box in boxes where box.roomId == room.id {
            remove("boxes", box.id, batch: batch)
        }
        for item in furniture where item.roomId == room.id {
            remove("furniture", item.id, batch: batch)
        }
        for var item in items where item.roomId == room.id {
            item.placement = Placement()
            put(item, in: "items", batch: batch)
        }
        batch.commit()
    }

    // MARK: - 櫃子

    func addCabinet(roomId: String, name: String, rows: Int, cols: Int) {
        guard let room = self.room(roomId), let id = newId("cabinets") else { return }
        let spot = freeSpot(in: room, w: 2, h: 1) ?? (x: 0, y: 0)
        put(Cabinet(id: id, roomId: roomId, name: name, rows: rows, cols: cols, x: spot.x, y: spot.y,
                    ownerUid: room.ownerUid, shared: room.shared), in: "cabinets")
    }

    /// 改名、改層數欄數。格子變少時，多出來那幾格的東西移到最後一層／欄。
    func updateCabinet(_ cabinet: Cabinet, name: String, rows: Int, cols: Int) {
        var updated = cabinet
        updated.name = name
        updated.rows = rows
        updated.cols = cols
        let batch = db.batch()
        put(updated, in: "cabinets", batch: batch)

        for var box in boxes where box.cabinetId == cabinet.id {
            if let r = box.row, let c = box.col, r >= rows || c >= cols {
                box.row = min(r, rows - 1)
                box.col = min(c, cols - 1)
                put(box, in: "boxes", batch: batch)
            }
        }
        for var item in items where item.boxId == nil && item.cabinetId == cabinet.id {
            if let r = item.row, let c = item.col, r >= rows || c >= cols {
                item.row = min(r, rows - 1)
                item.col = min(c, cols - 1)
                put(item, in: "items", batch: batch)
            }
        }
        batch.commit()
    }

    /// 刪除櫃子：裡面的盒子和物品留在同一個房間
    func deleteCabinet(_ cabinet: Cabinet) {
        let batch = db.batch()
        remove("cabinets", cabinet.id, batch: batch)
        for var box in boxes where box.cabinetId == cabinet.id {
            box.cabinetId = nil
            box.row = nil
            box.col = nil
            put(box, in: "boxes", batch: batch)
        }
        for var item in items where item.boxId == nil && item.cabinetId == cabinet.id {
            item.cabinetId = nil
            item.row = nil
            item.col = nil
            put(item, in: "items", batch: batch)
        }
        batch.commit()
    }

    // MARK: - 盒子

    func addBox(name: String, at placement: Placement) {
        guard let room = self.room(placement.roomId), let id = newId("boxes") else { return }
        put(Box(id: id, name: name, roomId: room.id,
                cabinetId: placement.cabinetId, row: placement.row, col: placement.col,
                ownerUid: room.ownerUid, shared: room.shared), in: "boxes")
    }

    func renameBox(_ box: Box, to name: String) {
        var updated = box
        updated.name = name
        put(updated, in: "boxes")
    }

    /// 移動盒子，裡面的物品自動跟著走
    func moveBox(_ box: Box, to placement: Placement) {
        guard let room = self.room(placement.roomId) else { return }
        var updated = box
        updated.roomId = room.id
        updated.cabinetId = placement.cabinetId
        updated.row = placement.row
        updated.col = placement.col
        updated.ownerUid = room.ownerUid
        updated.shared = room.shared

        let batch = db.batch()
        put(updated, in: "boxes", batch: batch)
        for var item in items where item.boxId == box.id {
            item.roomId = room.id
            item.ownerUid = room.ownerUid
            item.shared = room.shared
            put(item, in: "items", batch: batch)
        }
        batch.commit()
    }

    /// 刪除盒子：裡面的物品改成放在盒子原本的位置
    func deleteBox(_ box: Box) {
        let batch = db.batch()
        remove("boxes", box.id, batch: batch)
        for var item in items where item.boxId == box.id {
            item.placement = box.placement
            put(item, in: "items", batch: batch)
        }
        batch.commit()
    }

    // MARK: - 物品

    @discardableResult
    func saveItem(_ item: Item) -> Item {
        var item = item
        if item.id.isEmpty, let id = newId("items") { item.id = id }
        if item.ownerUid.isEmpty, let uid { item.ownerUid = uid }

        // 放在盒子裡：位置跟著盒子
        if let box = self.box(item.boxId) {
            item.roomId = box.roomId
            item.cabinetId = nil
            item.row = nil
            item.col = nil
        } else {
            item.boxId = nil
        }
        // 放在房間裡：誰看得到跟著房間
        if let room = self.room(item.roomId) {
            item.ownerUid = room.ownerUid
            item.shared = room.shared
        }
        put(item, in: "items")
        return item
    }

    func deleteItem(_ item: Item) {
        remove("items", item.id)
    }

    func markUsed(_ item: Item) {
        var updated = item
        updated.lastUsedDate = Date()
        put(updated, in: "items")
    }

    func changeQuantity(_ item: Item, by delta: Int) {
        let old = item.quantity ?? 0
        let new = max(0, old + delta)
        var updated = item
        updated.quantity = new
        put(updated, in: "items")
        if let threshold = item.restockThreshold, old > threshold, new <= threshold {
            NotificationManager.shared.notifyRestock(name: item.name, quantity: new, id: item.id)
        }
    }
    // MARK: - 地圖（網格地板）

        func furniture(in roomId: String) -> [Furniture] {
            furniture.filter { $0.roomId == roomId }
        }

        /// 房間裡被櫃子和傢俱佔用的格子（可以排除某一個，例如正在拖曳的那個）
        func occupiedRects(in roomId: String, excluding id: String? = nil) -> [GridRect] {
            let cabinetRects = cabinets(in: roomId).filter { $0.id != id }.map(\.rect)
            let furnitureRects = furniture(in: roomId).filter { $0.id != id }.map(\.rect)
            return cabinetRects + furnitureRects
        }

        /// 這個位置能不能放：不能超出地板，也不能和其他東西重疊
        func canPlace(_ rect: GridRect, in room: Room, excluding id: String? = nil) -> Bool {
            guard rect.x >= 0, rect.y >= 0,
                  rect.x + rect.w <= room.gridW, rect.y + rect.h <= room.gridH else { return false }
            return !occupiedRects(in: room.id, excluding: id).contains { $0.intersects(rect) }
        }

        /// 從左上角開始找第一個放得下的空位
        func freeSpot(in room: Room, w: Int, h: Int, excluding id: String? = nil) -> (x: Int, y: Int)? {
            guard w <= room.gridW, h <= room.gridH else { return nil }
            for y in 0...(room.gridH - h) {
                for x in 0...(room.gridW - w) {
                    if canPlace(GridRect(x: x, y: y, w: w, h: h), in: room, excluding: id) {
                        return (x, y)
                    }
                }
            }
            return nil
        }

        func updateCabinetLayout(_ cabinet: Cabinet, x: Int, y: Int, w: Int, h: Int, rotated: Bool) {
            var updated = cabinet
            updated.x = x
            updated.y = y
            updated.w = w
            updated.h = h
            updated.rotated = rotated
            put(updated, in: "cabinets")
        }

        /// 新增傢俱，自動放在第一個空位。沒有空位時回傳 false。
        @discardableResult
        func addFurniture(roomId: String, kind: FurnitureKind) -> Bool {
            guard let room = self.room(roomId), let id = newId("furniture") else { return false }
            let size = kind.defaultSize
            guard let spot = freeSpot(in: room, w: size.w, h: size.h) else { return false }
            put(Furniture(id: id, roomId: roomId, kindRaw: kind.rawValue,
                          x: spot.x, y: spot.y, w: size.w, h: size.h,
                          ownerUid: room.ownerUid, shared: room.shared), in: "furniture")
            return true
        }

        func updateFurniture(_ item: Furniture) {
            put(item, in: "furniture")
        }

        func deleteFurniture(_ item: Furniture) {
            remove("furniture", item.id)
        }

        func updateRoomSize(_ room: Room, w: Int, h: Int) {
            var updated = room
            updated.gridW = w
            updated.gridH = h
            put(updated, in: "rooms")
        }

        /// 地板最小能縮到多大（不能把已經擺好的東西擠出去）
        func minimumSize(of room: Room) -> (w: Int, h: Int) {
            let rects = occupiedRects(in: room.id)
            let w = rects.map { $0.x + $0.w }.max() ?? 0
            let h = rects.map { $0.y + $0.h }.max() ?? 0
            return (max(3, w), max(3, h))
        }
}
