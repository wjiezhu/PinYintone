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

    private enum SubmitState { case editing, sending, sent, mailed, failed }

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
                        .onChange(of: detail) { new in
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
                        .foregroundStyle(Theme.primary)
                } else if state == .mailed {
                    // 走的是邮件，如实说明，不显示成「已提交」
                    Label(NSLocalizedString("issue_mail_opened", comment: ""),
                          systemImage: "envelope")
                        .foregroundStyle(Theme.textSecondary)
                } else if state == .failed {
                    Label(NSLocalizedString("issue_failed", comment: ""),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
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
                    .disabled(category == nil || state == .sending || state == .sent
                              || state == .mailed)
                }
            }
        }
    }

    private func submit() async {
        guard let category else { return }
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard ResearchGate.shouldCollect() else {
            // 没有研究身份（未参加、已退出、不在采集期）：**不写研究表**，
            // 也不假装反馈已进研究库——走知情说明里写明的联系渠道。
            openMail(category: category, detail: text)
            state = .mailed
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
///
/// 与其它研究写入同一道门禁：只有此刻在采集中才写研究表。
/// 报告编号在第一次尝试时生成并在重试时复用——网络失败后用户再点一次提交，
/// 服务端只会有一份。
@MainActor
enum IssueReporter {
    private static var pendingID: (key: String, id: String)?

    static func submit(category: String, detail: String?) async throws {
        let state = ResearchStore.shared.state
        guard ResearchGate.shouldCollect(),
              let pid = state.participantID, let mid = state.manifestID else { return }
        // 同样的内容重试时复用同一个 report_id
        let key = "\(category)|\(detail ?? "")"
        let reportID: String
        if let pending = pendingID, pending.key == key {
            reportID = pending.id
        } else {
            reportID = UUID().uuidString
            pendingID = (key, reportID)
        }
        try await APIClient.shared.reportIssue(
            reportID: reportID, participantID: pid, manifestID: mid,
            submittedAt: Date(), category: category, detail: detail)
        pendingID = nil
    }
}
