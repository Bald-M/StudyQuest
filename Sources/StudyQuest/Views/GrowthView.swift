import Charts
import StudyCore
import SwiftUI

/// 成长页：等级与经验、连续天数、10 个阶段的状态，以及历次考试得分折线。
struct GrowthView: View {
    let model: AppModel

    @State private var stages: [Stage] = []
    @State private var scores: [AppModel.ExamScore] = []
    @State private var loadError: String?

    var body: some View {
        Form {
            if let progress = model.progress { levelSection(progress) }
            trendSection
            Section("阶段") {
                ForEach(stages) { stage in
                    HStack {
                        Text("阶段 \(stage.index)：\(stage.title)")
                        Spacer()
                        statusLabel(stage.status)
                    }
                }
            }
            if let loadError { Text(loadError).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .navigationTitle("成长")
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
    }

    private func levelSection(_ progress: ProgressSummary) -> some View {
        let base = XPRules.xpForNextLevel(progress.level - 1)
        let span = max(1, progress.nextLevelXP - base)
        return Section {
            HStack(spacing: 24) {
                Text("Lv.\(progress.level)").font(.largeTitle.bold())
                Label("总经验 \(progress.xp)", systemImage: "star.fill").foregroundStyle(.orange)
                Label("连续 \(progress.streak) 天", systemImage: "flame.fill").foregroundStyle(.red)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(progress.xp - base), total: Double(span))
                Text("\(progress.xp - base) / \(span) 经验升级").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var trendSection: some View {
        Section("考试得分") {
            if scores.isEmpty {
                Text("还没有已判卷的考试").foregroundStyle(.secondary)
            } else {
                Chart(scores) { score in
                    LineMark(x: .value("判卷时间", score.gradedAt), y: .value("得分", score.percent))
                    PointMark(x: .value("判卷时间", score.gradedAt), y: .value("得分", score.percent))
                        .foregroundStyle(score.passed == true ? Color.green : Color.red)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 200)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private func statusLabel(_ status: StageStatus) -> some View {
        switch status {
        case .locked: Label("未解锁", systemImage: "lock.fill").foregroundStyle(.secondary)
        case .inProgress: Label("进行中", systemImage: "play.circle.fill").foregroundStyle(.blue)
        case .passed: Label("已通过", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        }
    }

    private func reload() {
        do {
            stages = try model.stages()
            scores = try model.examScores()
            loadError = nil
        } catch {
            loadError = userMessage(error)
        }
    }
}
