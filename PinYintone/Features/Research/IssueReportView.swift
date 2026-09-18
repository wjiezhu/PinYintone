import SwiftUI

/// 「报告问题」入口（字典 §12）。**始终可用**，不要求先完成任何练习。
///
/// 按研究身份分流：
/// - 已纳入研究 → 写入 research_issue_reports
/// - 未纳入（谢绝、不合格、未邀请）→ **不进研究表**（字典 §12：
///   「非研究用户也可使用产品问题反馈，但其业务反馈不进入本研究表」），
///   改走知情说明里写明的联系渠道。
struct IssueReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var category: String?
    @State private var detail = ""
    @State private var state: SubmitState = .editing

    private enum SubmitState { case editing, sending, sent, failed }

    /// 与 POST04 同一组类别，便于和问卷回答对照（但二者**分别统计**）
    private static let categories = ["cannot_find_action", "recording_failed",
                                     "analysis_failed", "app_crashed",
                                     "unclear_feedback", "other"]
    private static let maxChars = 500

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("issue_category_title", comment: "")) {
                    ForEach(Self.categories, id: \.self) { c in
                        Button {
                            category = c
                        } label: {
                            HStack {
                                Text(NSLocalizedString("issue_cat_\(c)", comment: ""))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if category == c {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextEditor(text: $detail)
                        .frame(minHeight: 110)
                        // 按 Unicode 字符截断，不按字节——阿拉伯文按字节会被误判超长
                        .onChange(of: detail) { _, new in
                            if new.count > Self.maxChars { detail = String(new.prefix(Self.maxChars)) }
                        }
                } header: {
                    Text(NSLocalizedString("issue_detail_title", comment: ""))
                } footer: {
                    Text(NSLocalizedString("survey_privacy_hint", comment: ""))
                }

                if state == .sent {
                    Label(NSLocalizedString("issue_sent", comment: ""),
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else if state == .failed {
                    Label(NSLocalizedString("issue_failed", comment: ""),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle(NSLocalizedString("issue_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common_close", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("survey_submit", comment: "")) {
                        Task { await submit() }
                    }
                    .disabled(category == nil || state == .sending || state == .sent)
                }
            }
        }
    }

    private func submit() async {
        guard let category else { return }
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard ResearchIdentity.shared.isEnrolled,
              ResearchConsent.shared.allowsResearchCollection else {
            // 非研究用户：不写研究表，走知情说明中的联系渠道
            openMail(category: category, detail: text)
            state = .sent
            return
        }

        state = .sending
        do {
            try await IssueReporter.submit(category: category,
                                           detail: text.isEmpty ? nil : text)
            state = .sent
        } catch {
            state = .failed
        }
    }

    private func openMail(category: String, detail: String) {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = "joyouo409@gmail.com"
        c.queryItems = [
            .init(name: "subject", value: "Pinyintone: \(category)"),
            .init(name: "body", value: detail),
        ]
        if let url = c.url { openURL(url) }
    }
}

/// 研究用户的问题上报。
@MainActor
enum IssueReporter {
    static func submit(category: String, detail: String?) async throws {
        let id = ResearchIdentity.shared
        guard let pid = id.participantID, let mid = id.manifestID else { return }
        try await APIClient.shared.reportIssue(
            reportID: UUID().uuidString, participantID: pid, manifestID: mid,
            submittedAt: Date(), category: category, detail: detail)
    }
}
