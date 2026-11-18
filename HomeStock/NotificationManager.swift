import Foundation
import UserNotifications

// 所有通知都是 iPhone 本機通知，不需要伺服器。
// iOS 同時最多只能排 64 則，所以每次都重新計算，只排最近的 60 則。
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// App 開著的時候也要顯示通知橫幅
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private struct Pending {
        let date: Date
        let id: String
        let title: String
        let body: String
    }

    /// 重新排程所有「有效日期」與「使用週期」通知。物品有變動時呼叫。
    func rescheduleAll(items: [Item]) {
        let hour = UserDefaults.standard.object(forKey: "notifyHour") as? Int ?? 9
        let cal = Calendar.current
        let now = Date()
        let nextSlot = cal.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: 0),
            matchingPolicy: .nextTime
        )
        var pending: [Pending] = []

        for item in items {
            // 有效日期：到期前 N 天通知
            if let expiry = item.expiryDate {
                let expiryDay = cal.startOfDay(for: expiry)
                let endOfExpiryDay = cal.date(byAdding: .day, value: 1, to: expiryDay) ?? expiryDay
                let notifyDay = cal.date(byAdding: .day, value: -item.expiryNotifyDaysBefore, to: expiryDay) ?? expiryDay
                var fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: notifyDay)
                // 已經進入提醒期但還沒過期：改在下一個通知時間提醒
                if let f = fire, f <= now { fire = nextSlot }
                if let fire, fire < endOfExpiryDay {
                    let daysLeft = cal.dateComponents([.day], from: cal.startOfDay(for: fire), to: expiryDay).day ?? 0
                    let body = daysLeft <= 0
                        ? "「\(item.name)」今天到期"
                        : "「\(item.name)」還有 \(daysLeft) 天到期"
                    pending.append(Pending(date: fire, id: "exp-\(item.id)", title: "有效日期提醒", body: body))
                }
            }

            // 使用週期：距離上次使用滿 N 天通知
            if let next = item.nextUseDate {
                var fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: next)
                if let f = fire, f <= now { fire = nextSlot }
                if let fire {
                    pending.append(Pending(
                        date: fire,
                        id: "use-\(item.id)",
                        title: "該使用／更換了",
                        body: "「\(item.name)」\(item.intervalText ?? "")要使用或更換一次"
                    ))
                }
            }
        }

        pending.sort { $0.date < $1.date }
        center.removeAllPendingNotificationRequests()

        for entry in pending.prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: entry.id, content: content, trigger: trigger))
        }
    }

    /// 數量降到門檻以下時，立刻通知補貨
    func notifyRestock(name: String, quantity: Int, id: String) {
        let content = UNMutableNotificationContent()
        content.title = "該補貨了"
        content.body = "「\(name)」只剩 \(quantity) 個"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        center.add(UNNotificationRequest(identifier: "stock-\(id))", content: content, trigger: trigger))
    }

    /// 設定頁的測試按鈕
    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "測試通知"
        content.body = "看到這則代表通知功能正常"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
    }
}
