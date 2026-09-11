import SwiftUI

/// 教练提示卡：把评分结果翻译成**一句可执行的话**。
///
/// 设计约束（技术要求档案 §4.3）：每次反馈最多突出**一个**主要调整方向。
/// 这里把它做成版式约束——卡片只放得下一条主提示 + 一句鼓励，想堆也堆不进去。
///
/// 提示完全由本地派生指标（分段 DTW + 方向判断）套本地化模板生成，
/// **不需要云端**；无法判定时降级为技术性重录提示，不硬编一个可能是错的诊断。
///
/// 只在 `training` 阶段出现；裸测阶段任何评价性 UI 都不得渲染。
struct CoachCardView: View {
    let advice: CoachAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("coach_title", comment: ""))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(Color.accentColor)

            Text(mainSentence)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let praise = advice.praiseChar {
                Text(String(format: NSLocalizedString("coach_praise", comment: ""), praise))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// 全对时不需要待改的字，模板里也就没有 `%@` 占位符
    private var mainSentence: String {
        let template = NSLocalizedString(advice.hint.coachKey, comment: "")
        guard let char = advice.focusChar else { return template }
        return String(format: template, char)
    }
}
