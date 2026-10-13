import SwiftUI

/// 目标词：汉字 + 拼音 + 释义。声调练习、自测、自由文本通用。
///
/// 一次只回答一个问题——**这次要念什么**。不做成卡片，直接排在内容区里。
/// 汉字与拼音的排列方向固定从左到右：阿拉伯语界面下整页是从右到左，
/// 但中文词的字序不能跟着镜像。
struct LexemeCardView: View {
    let lexeme: Lexeme
    @ObservedObject private var localization = LocalizationManager.shared
    /// 汉字 40pt 起，随系统文字大小缩放（不随屏幕宽度缩放）
    @ScaledMetric(relativeTo: .largeTitle) private var hanziSize: CGFloat = 40

    var body: some View {
        let gloss = lexeme.glosses(for: localization.language)
        VStack(spacing: Theme.Space.xs) {
            Text(lexeme.hanzi)
                .font(.system(size: hanziSize, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("practice.hanzi")
            Text(lexeme.pinyin)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .environment(\.layoutDirection, .leftToRight)
            if !gloss.primary.isEmpty {
                Text(gloss.primary)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.xs)
            }
            if let secondary = gloss.secondary {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 不显示 lexeme.focus：那是语料的「考察重点」标注（中文、面向研究者），
            // 自测时还等于提前告知这题考什么。它仍保留在语料与导出数据里。
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
