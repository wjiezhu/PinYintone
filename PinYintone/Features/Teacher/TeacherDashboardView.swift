import SwiftUI
import UIKit

/// 教师端主页：极简只读数据面板（无训练功能、无侧边栏）
struct TeacherDashboardView: View {
    @StateObject private var vm = TeacherDashboardViewModel()
    @EnvironmentObject var userManager: UserManager
    @State private var showSettings = false

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 顶部：教师姓名 + 班级码（可复制/分享）
                    TeacherHeaderView(
                        name: profile?.nickname ?? "教师",
                        classCode: profile?.classCode ?? "------"
                    )

                    // 离线提示
                    if let msg = vm.errorMessage {
                        offlineBanner(msg)
                    }

                    // 班级概览卡片
                    ClassOverviewCards(summary: vm.summary)

                    // A/B 两组对比图表
                    GroupComparisonChart(data: vm.groupData)

                    // 各声调偏误分布
                    ToneTypeBreakdown(data: vm.toneBreakdown)

                    // 学生列表
                    StudentListView(students: vm.students) { vm.openDetail($0) }

                    // CSV 导出
                    ExportButton { Task { await vm.exportCSV() } }
                }
                .padding(20)
            }
            .navigationTitle("班级数据面板")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay {
                if vm.isLoading && vm.summary == nil {
                    ProgressView().scaleEffect(1.2)
                }
            }
            .refreshable { await vm.refresh() }
            .task { await vm.refresh() }
            // 学生详情下钻
            .sheet(item: $vm.selectedStudent) { student in
                StudentDetailView(student: student)
            }
            // CSV 分享
            .sheet(isPresented: Binding(
                get: { vm.exportURL != nil },
                set: { if !$0 { vm.exportURL = nil } }
            )) {
                if let url = vm.exportURL {
                    ShareSheet(items: [url])
                }
            }
            // 设置
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(userManager)
            }
        }
    }

    private func offlineBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("离线模式：显示缓存数据")
                .font(.caption)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .foregroundStyle(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - UIActivityViewController 包装
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
