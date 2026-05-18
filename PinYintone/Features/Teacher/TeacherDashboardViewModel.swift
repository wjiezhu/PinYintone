import Combine
import Foundation

@MainActor
final class TeacherDashboardViewModel: ObservableObject {
    @Published var summary: ClassSummary?
    @Published var groupData: GroupComparisonData = .init()
    @Published var toneBreakdown: ToneBreakdownData = .init()
    @Published var students: [StudentRowData] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func refresh() async {
        fatalError("TODO: 实现 — 并发 async let 四接口 + cacheSnapshot")
    }

    func exportCSV() async {
        fatalError("TODO: 实现 — APIClient.exportClassCSV() → UIActivityViewController")
    }

    func openDetail(_ student: StudentRowData) {
        fatalError("TODO: 实现")
    }

    private func cacheSnapshot() {
        fatalError("TODO: 实现 — 序列化至 UserDefaults")
    }

    private func loadCachedSnapshot() {
        fatalError("TODO: 实现 — 反序列化 UserDefaults 离线缓存")
    }
}
