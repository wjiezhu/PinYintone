import SwiftUI

/// 游客输入班级码升级为学生的 Sheet
struct BindClassCodeSheet: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var classCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                Text(NSLocalizedString("bind_classcode_title", comment: ""))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(NSLocalizedString("bind_classcode_body", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                TextField(NSLocalizedString("signup_classcode_hint", comment: ""), text: $classCode)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onChange(of: classCode) { _, new in
                        if new.count > 6 { classCode = String(new.prefix(6)) }
                    }
                    .padding(.horizontal, 32)

                if let msg = errorMessage {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    bind()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(NSLocalizedString("bind_classcode_submit", comment: ""))
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(classCode.count == 6 ? Color.accentColor : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(classCode.count != 6 || isLoading)
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func bind() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await userManager.bindClassCode(classCode)
                dismiss()
            } catch let e as RegisterError {
                errorMessage = e.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
