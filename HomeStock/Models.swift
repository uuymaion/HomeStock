import Foundation

// 資料都存在 Firebase 雲端資料庫，每一筆都是一個 struct。
// shared / ownerUid 用來控制誰看得到：shared == true 全家看得到，否則只有 ownerUid 本人。

protocol HomeDoc: Codable, Identifiable, Hashable, Sendable {
    var id: String { get set }
    var createdAt: Date { get }
}

// MARK: - 家庭

struct Family: Codable, Sendable {
    var name: String
    var ownerUid: String
    var joinKey: String
    var createdAt: Date
}

struct Member: HomeDoc {
    var id: String = ""
    var name: String
    var joinKey: String
    var createdAt: Date = Date()
}

// MARK: - 標籤（全家共用）

enum TagKind: String, CaseIterable, Identifiable, Sendable {
    case category   // 大分類（每個物品最多一個，沒有就是「未分類」）
    case sub        // 小標籤（可自由組合多個）
    case brand      // 品牌

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: return "大分類"
        case .sub: return "小標籤"
        case .brand: return "品牌"
        }
    }
}

struct ItemTag: HomeDoc {
    var id: String = ""
    var name: String
    var kindRaw: String
    var createdAt: Date = Date()

    var kind: TagKind { TagKind(rawValue: kindRaw) ?? .sub }
}

// MARK: - 位置：房間 → 櫃子（層 × 欄）→ 盒子

struct Room: HomeDoc {
    var id: String = ""
    var name: String
    var ownerUid: String
    var shared: Bool
    var gridW: Int = 10      // 網格地板預設 10 × 8 格（下一階段的地圖會用到）
    var gridH: Int = 8
    var createdAt: Date = Date()
}

struct Cabinet: HomeDoc {
    var id: String = ""
    var roomId: String
    var name: String
    var rows: Int = 3        // 層
    var cols: Int = 1        // 欄
    var x: Int = 0           // 以下是在網格地板上的位置與大小（下一階段用）
    var y: Int = 0
    var w: Int = 2
    var h: Int = 1
    var rotated: Bool = false
    var ownerUid: String
    var shared: Bool
    var createdAt: Date = Date()
}

/// 盒子：可以放在櫃子的某一格，也可以直接放在房間裡
struct Box: HomeDoc {
    var id: String = ""
    var name: String
    var roomId: String
    var cabinetId: String? = nil
    var row: Int? = nil
    var col: Int? = nil
    var ownerUid: String
    var shared: Bool
    var createdAt: Date = Date()
}

/// 傢俱：只當裝飾（下一階段的地圖會用到）
struct Furniture: HomeDoc {
    var id: String = ""
    var roomId: String
    var kindRaw: String
    var name: String? = nil      // 自訂傢俱的名稱
    var symbol: String? = nil    // 自訂傢俱的圖示
    var x: Int = 0
    var y: Int = 0
    var w: Int = 1
    var h: Int = 1
    var rotated: Bool = false
    var ownerUid: String
    var shared: Bool
    var createdAt: Date = Date()
}

/// 物品放在哪裡。全部是 nil 代表未指定位置。
struct Placement: Equatable, Sendable {
    var roomId: String? = nil
    var cabinetId: String? = nil
    var row: Int? = nil
    var col: Int? = nil
    var boxId: String? = nil
}

// MARK: - 物品

struct Item: HomeDoc {
    var id: String = ""
    var name: String
    var tagIds: [String] = []

    // 位置：放在盒子裡時只看 boxId（roomId 會跟著盒子）
    var roomId: String? = nil
    var cabinetId: String? = nil
    var row: Int? = nil
    var col: Int? = nil
    var boxId: String? = nil

    // 有效日期
    var expiryDate: Date? = nil
    var expiryNotifyDaysBefore: Int = 7

    // 使用週期
    var usageIntervalDays: Int? = nil
    var lastUsedDate: Date? = nil

    // 數量與補貨
    var quantity: Int? = nil
    var restockThreshold: Int? = nil

    var ownerUid: String = ""
    var shared: Bool = true
    var createdAt: Date = Date()
}

extension Item {
    var placement: Placement {
        get { Placement(roomId: roomId, cabinetId: cabinetId, row: row, col: col, boxId: boxId) }
        set {
            roomId = newValue.roomId
            cabinetId = newValue.cabinetId
            row = newValue.row
            col = newValue.col
            boxId = newValue.boxId
        }
    }
}

extension Box {
    var placement: Placement {
        Placement(roomId: roomId, cabinetId: cabinetId, row: row, col: col)
    }
}

// MARK: - 物品狀態

enum ItemStatus: Hashable {
    case expired(Int)        // 已過期幾天
    case expiringSoon(Int)   // 還剩幾天
    case useDue
    case restock

    var text: String {
        switch self {
        case .expired(let days): return days == 0 ? "今天到期" : "已過期 \(days) 天"
        case .expiringSoon(let days): return days == 0 ? "今天到期" : "剩 \(days) 天到期"
        case .useDue: return "該使用了"
        case .restock: return "該補貨"
        }
    }

    var isDanger: Bool {
        if case .expired = self { return true }
        return false
    }
}

extension Item {
    /// 下次該使用的日期
    var nextUseDate: Date? {
        guard let days = usageIntervalDays, days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: lastUsedDate ?? createdAt)
    }

    /// 距離到期還有幾天（負數代表已過期）
    var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: expiryDate)).day
    }

    var needsRestock: Bool {
        guard let quantity, let restockThreshold else { return false }
        return quantity <= restockThreshold
    }

    var intervalText: String? {
        guard let days = usageIntervalDays, days > 0 else { return nil }
        if days % 30 == 0 { return "每 \(days / 30) 個月" }
        if days % 7 == 0 { return "每 \(days / 7) 週" }
        return "每 \(days) 天"
    }

    func statuses() -> [ItemStatus] {
        var result: [ItemStatus] = []
        if let days = daysUntilExpiry {
            if days < 0 {
                result.append(.expired(-days))
            } else if days <= expiryNotifyDaysBefore {
                result.append(.expiringSoon(days))
            }
        }
        if let next = nextUseDate {
            let cal = Calendar.current
            if cal.startOfDay(for: next) <= cal.startOfDay(for: Date()) {
                result.append(.useDue)
            }
        }
        if needsRestock { result.append(.restock) }
        return result
    }

    /// 排序用：最近需要處理的日期
    var urgencyDate: Date {
        let candidates = [expiryDate, nextUseDate].compactMap { $0 }
        return candidates.min() ?? .distantFuture
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
