import SwiftUI

/// 逐词练习界面：当前词 + 拼音 + 实时 F0 可视化 + 导航
struct FreeWordPracticeView: View {
    let tokens: [String]
    @StateObject private var vm = FreeWordPracticeViewModel()
    @State private var currentIndex: Int = 0

    var body: some View {
        fatalError("TODO: 实现 — 进度条 + FreeF0Canvas + RecordButton + 上/下一词")
    }
}
