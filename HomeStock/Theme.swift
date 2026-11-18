import SwiftUI
import UIKit

// 暗藍 + 紫色主題
enum Theme {
    static let bg = Color(red: 0.04, green: 0.06, blue: 0.15)
    static let card = Color(red: 0.09, green: 0.12, blue: 0.25)
    static let cardHigh = Color(red: 0.14, green: 0.17, blue: 0.34)
    static let accent = Color(red: 0.62, green: 0.45, blue: 1.0)
    static let accentSoft = Color(red: 0.42, green: 0.33, blue: 0.80)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.52)
    static let subtext = Color(red: 0.66, green: 0.70, blue: 0.88)
}

extension View {
    /// 套用在 List / Form 上，換成暗藍背景
    func themedList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .toolbarBackground(Theme.bg, for: .navigationBar)
    }
}

/// 小膠囊標籤
struct Chip: View {
    let text: String
    var color: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : color)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.18))
            )
    }
}

/// 物品的狀態徽章（快過期／該使用／該補貨）
struct StatusBadges: View {
    let item: Item

    var body: some View {
        let statuses = item.statuses()
        if !statuses.isEmpty {
            HStack(spacing: 6) {
                ForEach(statuses, id: \.self) { status in
                    Chip(text: status.text, color: status.isDanger ? Theme.danger : Theme.warn)
                }
            }
        }
    }
}

/// 列表尾端「輸入名稱 + 加入」的共用列
struct AddRow: View {
    let placeholder: String
    let onAdd: (String) -> Void
    @State private var text = ""

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .onSubmit(submit)
            Button("加入", action: submit)
                .buttonStyle(.borderless)
                .disabled(trimmed.isEmpty)
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        text = ""
    }
}

enum ImageTools {
    /// 把照片縮小並壓成 JPEG，避免資料庫變得太大
    static func compress(_ data: Data, maxSide: CGFloat = 1000) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let ratio = longest > maxSide ? maxSide / longest : 1
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
