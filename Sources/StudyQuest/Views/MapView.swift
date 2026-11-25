import StudyCore
import SwiftUI

/// 10 阶段路线图：之字形节点连成一条路，点击进入阶段详情。
struct MapView: View {
    let model: AppModel

    @State private var stages: [Stage] = []
    @State private var loadError: String?

    private let rowHeight: CGFloat = 112
    private let nodeSize: CGFloat = 64

    var body: some View {
        NavigationStack {
            Group {
                if stages.isEmpty {
                    ContentUnavailableView(loadError ?? "没有阶段数据", systemImage: "map")
                } else {
                    ScrollView { route }
                }
            }
            .navigationTitle("地图")
            .navigationDestination(for: Int.self) { StageDetailView(model: model, stageIndex: $0) }
        }
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
    }

    private var route: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                connectors(width: width)
                VStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.index) { offset, stage in
                        node(stage, onLeft: offset.isMultiple(of: 2), width: width)
                            .frame(height: rowHeight)
                    }
                }
            }
        }
        .frame(height: rowHeight * CGFloat(stages.count))
        .padding(.vertical, 8)
    }

    private func centerX(_ offset: Int, width: CGFloat) -> CGFloat { offset.isMultiple(of: 2) ? width * 0.3 : width * 0.7 }

    private func connectors(width: CGFloat) -> some View {
        Canvas { context, _ in
            for offset in 0..<max(0, stages.count - 1) {
                var path = Path()
                path.move(to: CGPoint(x: centerX(offset, width: width), y: rowHeight * (CGFloat(offset) + 0.5)))
                path.addLine(to: CGPoint(x: centerX(offset + 1, width: width), y: rowHeight * (CGFloat(offset) + 1.5)))
                let reached = stages[offset + 1].status != .locked
                context.stroke(path, with: .color(reached ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: reached ? [] : [2, 8]))
            }
        }
    }

    private func node(_ stage: Stage, onLeft: Bool, width: CGFloat) -> some View {
        let edge = max(0, width * 0.3 - nodeSize / 2)
        let label = VStack(alignment: onLeft ? .leading : .trailing, spacing: 2) {
            Text("阶段 \(stage.index)").font(.caption).foregroundStyle(.secondary)
            Text(stage.title).font(.headline).foregroundStyle(stage.status == .locked ? .secondary : .primary)
            Text(stage.estimatedWeeks).font(.caption).foregroundStyle(.secondary)
        }
        return NavigationLink(value: stage.index) {
            HStack(spacing: 12) {
                if onLeft {
                    circle(stage)
                    label
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    label
                    circle(stage)
                }
            }
            .padding(.leading, onLeft ? edge : 0)
            .padding(.trailing, onLeft ? 0 : edge)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("阶段 \(stage.index) \(stage.title)，\(statusText(stage.status))")
    }

    private func circle(_ stage: Stage) -> some View {
        ZStack {
            Circle().fill(fill(stage.status)).frame(width: nodeSize, height: nodeSize)
            switch stage.status {
            case .locked: Image(systemName: "lock.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
            case .inProgress: Text("\(stage.index)").font(.title.bold()).foregroundStyle(.white)
            case .passed: Image(systemName: "checkmark").font(.title.bold()).foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            // 每个阶段的考试是一个 Boss
            Label("Boss", systemImage: "flame.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(stage.status == .locked ? Color.gray : Color.red, in: Capsule())
                .foregroundStyle(.white)
                .offset(x: 14, y: -6)
        }
    }

    private func fill(_ status: StageStatus) -> Color {
        switch status {
        case .locked: .gray.opacity(0.55)
        case .inProgress: .accentColor
        case .passed: .green
        }
    }

    private func statusText(_ status: StageStatus) -> String {
        switch status {
        case .locked: "未解锁"
        case .inProgress: "进行中"
        case .passed: "已通过"
        }
    }

    private func reload() {
        do {
            stages = try model.stages()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
