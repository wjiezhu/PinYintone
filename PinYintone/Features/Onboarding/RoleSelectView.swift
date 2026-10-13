import SwiftUI

/// 账号入口：学生（Sign in with Apple）或教师。
struct RoleSelectView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                BrandHeader()
                    .padding(.top, Theme.Space.xl)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(key: "role_select_title")
                    NavigationLink {
                        StudentSignupView()
                    } label: {
                        EntryRow(icon: "graduationcap",
                                 title: NSLocalizedString("role_student", comment: ""))
                            .surfaceCard(padding: Theme.Space.m)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("role.student")

                    NavigationLink {
                        TeacherSignupView()
                    } label: {
                        EntryRow(icon: "person.2",
                                 title: NSLocalizedString("role_teacher", comment: ""))
                            .surfaceCard(padding: Theme.Space.m)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("role.teacher")
                }

                NavigationLink {
                    LanguagePickerPage()
                } label: {
                    Label(NSLocalizedString("settings_language", comment: ""), systemImage: "globe")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                        .frame(minHeight: Theme.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("role.language")
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 登录前改界面语言（选错了语言的人不该被困在看不懂的登录页上）
struct LanguagePickerPage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LanguageChoiceList(marksCurrent: true) { dismiss() }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.vertical, Theme.Space.l)
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("settings_language", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
