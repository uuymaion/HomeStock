import SwiftUI
import UIKit

// 第一次開啟：建立家庭，或用代碼和密碼加入家庭
struct FamilySetupView: View {
    @EnvironmentObject private var store: HomeStore

    enum Mode: String, CaseIterable, Identifiable {
        case create = "建立家庭"
        case join = "加入家庭"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .create
    @State private var familyName = ""
    @State private var nickname = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var errorText: String?

    private var canSubmit: Bool {
        guard !nickname.trimmed.isEmpty else { return false }
        switch mode {
        case .create:
            return !familyName.trimmed.isEmpty && password.count >= 4 && password == confirm
        case .join:
            return code.trimmed.count == 6 && !password.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("歡迎使用")
                            .font(.title2.bold())
                        Text("先建立一個家庭，或輸入家人給你的家庭代碼加入。")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtext)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    Picker("模式", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("你的暱稱（家人看得到）", text: $nickname)
                    if mode == .create {
                        TextField("家庭名稱，例如：陳家", text: $familyName)
                        SecureField("設定密碼（至少 4 個字）", text: $password)
                        SecureField("再輸入一次密碼", text: $confirm)
                    } else {
                        TextField("家庭代碼（6 碼）", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        SecureField("密碼", text: $password)
                    }
                } footer: {
                    if mode == .create && !confirm.isEmpty && password != confirm {
                        Text("兩次輸入的密碼不一樣")
                            .foregroundStyle(Theme.danger)
                    }
                }
                .listRowBackground(Theme.card)

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if working {
                                ProgressView()
                            } else {
                                Text(mode.rawValue).bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || working)
                } footer: {
                    Text("需要連上網路。")
                }
                .listRowBackground(Theme.accent.opacity(canSubmit ? 0.35 : 0.12))
            }
            .themedList()
            .navigationTitle("家庭")
            .onChange(of: mode) { _, _ in
                errorText = nil
                password = ""
                confirm = ""
            }
        }
    }

    private func submit() {
        working = true
        errorText = nil
        Task {
            do {
                if mode == .create {
                    _ = try await store.createFamily(
                        familyName: familyName.trimmed,
                        nickname: nickname.trimmed,
                        password: password
                    )
                } else {
                    try await store.joinFamily(code: code, password: password, nickname: nickname.trimmed)
                }
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }
}

// 設定頁裡的家庭管理
struct FamilySettingsView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var showPassword = false
    @State private var newPassword = ""
    @State private var confirmLeave = false
    @State private var message: String?

    var body: some View {
        List {
            Section("家庭") {
                LabeledContent("名稱", value: store.family?.name ?? "")
                HStack {
                    LabeledContent("家庭代碼", value: store.familyId ?? "")
                    Button {
                        UIPasteboard.general.string = store.familyId
                        message = "已複製家庭代碼"
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach(store.members) { member in
                    HStack {
                        Text(member.name)
                        Spacer()
                        if member.id == store.uid {
                            Chip(text: "我")
                        }
                        if member.id == store.family?.ownerUid {
                            Chip(text: "建立者", color: Theme.warn)
                        }
                    }
                    .swipeActions {
                        if store.isFamilyOwner && member.id != store.uid {
                            Button("移除", role: .destructive) {
                                store.removeMember(member)
                            }
                        }
                    }
                }
            } header: {
                Text("成員（\(store.members.count)）")
            } footer: {
                if store.isFamilyOwner {
                    Text("左滑可以移除家人。")
                }
            }
            .listRowBackground(Theme.card)

            if store.isFamilyOwner {
                Section {
                    Button("變更家庭密碼") {
                        newPassword = ""
                        showPassword = true
                    }
                } footer: {
                    Text("變更後，新加入的人要用新密碼；已加入的家人不受影響。")
                }
                .listRowBackground(Theme.card)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(Theme.subtext)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                Button("離開這個家庭", role: .destructive) {
                    confirmLeave = true
                }
            } footer: {
                Text(store.isFamilyOwner
                     ? "你是建立者。離開後沒有人能管理成員和密碼，建議不要離開。"
                     : "離開後這支手機看不到家庭資料，之後可以用代碼和密碼重新加入。")
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("家庭")
        .navigationBarTitleDisplayMode(.inline)
        .alert("變更家庭密碼", isPresented: $showPassword) {
            SecureField("新密碼（至少 4 個字）", text: $newPassword)
            Button("變更", action: changePassword)
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("確定要離開家庭嗎？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("離開", role: .destructive) { store.leaveFamily() }
            Button("取消", role: .cancel) {}
        }
    }

    private func changePassword() {
        guard newPassword.count >= 4 else {
            message = "密碼至少要 4 個字"
            return
        }
        let password = newPassword
        Task {
            do {
                try await store.changePassword(password)
                message = "密碼已變更"
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
