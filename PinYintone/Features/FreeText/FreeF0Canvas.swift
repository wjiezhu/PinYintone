import SwiftUI

/// 实时 F0 曲线画布（关卡 3 专用）
/// 无母语者参照：仅展示学习者实时轨迹 + 理想声调形状
struct FreeF0Canvas: View {
    let studentF0: [Float]
    let idealToneShape: [Float]
    let tones: [Int]

    var body: some View {
        fatalError("TODO: 实现 — Canvas 双线绘制（idealShape 灰色虚线 + studentF0 紫色实线）")
    }
}
