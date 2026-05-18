import SwiftUI

/// 自动换行流式布局（iOS 16+）
/// 用于 TokenEditorView 词条芯片、教师面板声调标签等
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        fatalError("TODO: 实现 — Layout protocol（iOS 16 _VariadicView 或自定义 Layout）")
    }
}
