import SwiftUI

/// 关卡 3 入口：粘贴/输入中文文本 → 触发自动分词
struct FreeTextInputView: View {
    @State private var rawText: String = ""
    @State private var tokens: [String] = []
    @State private var showEditor: Bool = false

    var body: some View {
        fatalError("TODO: 实现 — TextEditor + 字数提示 + 分词按钮")
    }
}
