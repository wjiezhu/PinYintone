import SwiftUI

/// 角色选择页：[我是学生] [我是教师]
struct RoleSelectView: View {
    @State private var goStudent = false
    @State private var goTeacher = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(NSLocalizedString("role_select_title", comment: ""))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 16) {
                roleButton(
                    label: NSLocalizedString("role_student", comment: ""),
                    icon: "graduationcap.fill",
                    color: .blue
                ) { goStudent = true }

                roleButton(
                    label: NSLocalizedString("role_teacher", comment: ""),
                    icon: "person.badge.shield.checkmark.fill",
                    color: .purple
                ) { goTeacher = true }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $goStudent) { StudentSignupView() }
        .navigationDestination(isPresented: $goTeacher) { TeacherSignupView() }
    }

    private func roleButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36)
                Text(label)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
