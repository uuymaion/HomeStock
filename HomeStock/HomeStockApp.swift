import SwiftUI
import FirebaseCore

@main
struct HomeStockApp: App {
    @StateObject private var store: HomeStore

    init() {
        FirebaseApp.configure()
        NotificationManager.shared.setup()
        _store = StateObject(wrappedValue: HomeStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: HomeStore

    private var showCode: Binding<Bool> {
        Binding(
            get: { store.newFamilyCode != nil },
            set: { if !$0 { store.newFamilyCode = nil } }
        )
    }

    var body: some View {
        Group {
            if let error = store.startError {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accentSoft)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.subtext)
                    Button("重試") {
                        Task { await store.start() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if !store.ready {
                ProgressView("連線中…")
            } else if store.familyId == nil {
                FamilySetupView()
            } else {
                MainTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task {
            await store.start()
            await NotificationManager.shared.requestPermission()
        }
        .alert("家庭已建立", isPresented: showCode) {
            Button("好") { store.newFamilyCode = nil }
        } message: {
            Text("家庭代碼：\(store.newFamilyCode ?? "")\n把代碼和密碼告訴家人，他們就能加入。之後也可以在「設定 › 家庭」查看代碼。")
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ItemListView()
                .tabItem { Label("查詢", systemImage: "magnifyingglass") }

            NavigationStack {
                ItemFormView()
            }
            .tabItem { Label("登錄", systemImage: "plus.circle.fill") }

            NavigationStack {
                RoomListView()
            }
            .tabItem { Label("位置", systemImage: "cabinet") }

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
