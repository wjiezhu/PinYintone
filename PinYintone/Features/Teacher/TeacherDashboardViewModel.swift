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

    /// 点击学生行时打开的详情（sheet item）
    @Published var selectedStudent: StudentRowData?

    /// exportCSV 成功后写入的临时文件 URL（触发 shareSheet）
    @Published var exportURL: URL?

    // MARK: - Cache

    private struct Snapshot: Codable {
        var summary: ClassSummary?
        var groupBars: [GroupBar]
        var toneItems: [ToneErrorItem]
        var students: [StudentRowData]
    }
    private static let cacheKey = "pt_dashboard_snapshot"

    // MARK: - Public API

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            // 四个接口并发请求
            async let s  = APIClient.shared.fetchClassSummary()
            async let g  = APIClient.shared.fetchGroupComparison()
            async let t  = APIClient.shared.fetchToneBreakdown()
            async let st = APIClient.shared.fetchStudents()

            summary       = try await s
            groupData     = try await g
            toneBreakdown = try await t
            students      = try await st
            cacheSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            loadCachedSnapshot()    // 离线时降级使用本地缓存
        }
        isLoading = false
    }

    func exportCSV() async {
        // 从本地数据生成 CSV（不依赖后端，确保离线可用）
        var lines = ["nickname,totalSessions,recentPassRate,lastActiveAt"]
        let isoFmt = ISO8601DateFormatter()
        for s in students {
            let nick = (s.nickname ?? "guest").replacingOccurrences(of: ",", with: " ")
            let date = s.lastActiveAt.map { isoFmt.string(from: $0) } ?? ""
            lines.append("\(nick),\(s.totalSessions),\(String(format: "%.4f", s.recentPassRate)),\(date)")
        }
        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinyintone_class.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
    }

    func openDetail(_ student: StudentRowData) {
        selectedStudent = student
    }

    // MARK: - Private

    private func cacheSnapshot() {
        let snap = Snapshot(
            summary:    summary,
            groupBars:  groupData.bars,
            toneItems:  toneBreakdown.items,
            students:   students
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func loadCachedSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        summary             = snap.summary
        groupData.bars      = snap.groupBars
        toneBreakdown.items = snap.toneItems
        students            = snap.students
    }
}
