import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: HomeStore
    @AppStorage("notifyHour") private var notifyHour = 9
    @AppStorage("defaultNotifyDays") private var defaultNotifyDays = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("家庭") {
                    NavigationLink {
                        FamilySettingsView()
                    } label: {
                        LabeledContent(store.family?.name ?? "家庭", value: "代碼 \(store.familyId ?? "")")
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("每天通知時間", selection: $notifyHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    Stepper("新物品預設提前 \(defaultNotifyDays) 天通知", value: $defaultNotifyDays, in: 0...365)
                    Button("傳送測試通知") {
                        NotificationManager.shared.sendTest()
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("收不到通知時，請到 iPhone 的「設定 › 通知」確認這個 App 已允許通知。")
                }
                .listRowBackground(Theme.card)

                Section("資料管理") {
                    NavigationLink("標籤管理") {
                        TagManageView()
                    }
                }
                .listRowBackground(Theme.card)

                Section("尚未加入的功能") {
                    LabeledContent("網格地圖", value: "下一階段")
                    LabeledContent("AI 拍照辨識", value: "之後")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("設定")
            .onChange(of: notifyHour) { _, _ in
                NotificationManager.shared.rescheduleAll(items: store.items)
            }
        }
    }
}
