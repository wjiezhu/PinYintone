import SwiftUI

/// 按字诊断格：在反馈卡里展示每个汉字的分段评分 + 方向提示。
/// A、B 两组录完后共享此反馈视图（不影响 A/B 实验设计——训练时的视觉反馈才是自变量）。
///
/// 颜色规则:
/// - 通关（DTW ≤ 0.5）：绿色 + 对勾,无方向提示
/// - 未通关：红色边框 + 方向箭头 + 中文/外语提示
struct ToneDiagnosticGrid: View {
    let segments: [ToneSegmentResult]

    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("diagnostic_title", comment: ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(segments) { seg in
                        cell(for: seg)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for seg: ToneSegmentResult) -> some View {
        let color: Color = seg.passed ? .green : .red

        VStack(spacing: 6) {
            // 汉字 + 声调号小标
            ZStack(alignment: .topTrailing) {
                Text(seg.hanziChar)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(color.opacity(0.55), lineWidth: seg.passed ? 0 : 1.5)
                    )
                Text("\(seg.expectedTone)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(color)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }

            // 箭头 + 方向提示文字
            HStack(spacing: 3) {
                Image(systemName: seg.directionHint.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(NSLocalizedString(seg.directionHint.localizationKey, comment: ""))
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(color)
            .frame(width: 62)
        }
    }
}
