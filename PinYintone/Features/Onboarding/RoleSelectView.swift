import SwiftUI

/// 账号入口：学生（Sign in with Apple）或教师。
struct RoleSelectView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    StudentSignupView()
                } label: {
                    Label(NSLocalizedString("role_student", comment: ""),
                          systemImage: "graduationcap")
                        .frame(minHeight: Theme.minTap)
                }
                .accessibilityIdentifier("role.student")

                NavigationLink {
                    TeacherSignupView()
                } label: {
                    Label(NSLocalizedString("role_teacher", comment: ""),
                          systemImage: "person.badge.shield.checkmark")
                        .frame(minHeight: Theme.minTap)
                }
                .accessibilityIdentifier("role.teacher")
            } header: {
                Text(NSLocalizedString("role_select_title", comment: ""))
            }

            Section {
                NavigationLink {
                    LanguagePickerPage()
                } label: {
                    Label(NSLocalizedString("settings_language", comment: ""), systemImage: "globe")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Pinyintone")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
    }
}

/// 登录前改界面语言（选错了语言的人不该被困在看不懂的登录页上）
struct LanguagePickerPage: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(LocalizationManager.supported, id: \.code) { lang in
                Button {
                    localization.setLanguage(lang.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(lang.label).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if localization.language == lang.code {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("settings_language", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
