import StudyCore
import SwiftUI

/// 模拟面试：聊天、结束并评分。`interviewId` 为 nil 时第一次发送才建立面试记录。
struct InterviewView: View {
    let model: AppModel
    @State var interviewId: Int64?
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, interviewId: Int64?) {
        self.model = model
        _interviewId = State(initialValue: interviewId)
    }

    @State private var interview: MockInterview?
    @State private var draft = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var recentAverage: Double?
    @State private var recentCount = 0

    private var transcript: [ChatTurn] { interview?.transcript ?? [] }
    private var finished: Bool { interview?.score != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模拟面试").font(.title3.bold())
                if let recentAverage {
                    Text("最近 \(recentCount) 场平均 \(Int(recentAverage.rounded())) 分").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if transcript.isEmpty {
                            Text("先向面试官打个招呼，例如「我准备好了」，面试官会开始提问。").foregroundStyle(.secondary)
                        }
                        ForEach(Array(transcript.enumerated()), id: \.offset) { offset, turn in
                            bubble(turn).id(offset)
                        }
                        if working { ProgressView().controlSize(.small).padding(8).id("working") }
                        if let interview, let score = interview.score { resultBox(score, interview) }
                    }
                    .padding(20)
                }
                .onChange(of: transcript.count) { withAnimation { proxy.scrollTo(transcript.count - 1, anchor: .bottom) } }
            }
            Divider()
            inputBar
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear(perform: load)
    }

    private func bubble(_ turn: ChatTurn) -> some View {
        let mine = turn.role == "user"
        return HStack {
            if mine { Spacer(minLength: 60) }
            Text(turn.content).textSelection(.enabled).padding(10)
                .background(mine ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            if !mine { Spacer(minLength: 60) }
        }
    }

    private func resultBox(_ score: Double, _ interview: MockInterview) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Int(score.rounded())) 分").font(.largeTitle.bold())
                if let feedback = interview.feedback { Text(feedback).textSelection(.enabled) }
                if let grader = interview.grader { Text("评分模型：\(grader)").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
            HStack(alignment: .bottom) {
                TextEditor(text: $draft)
                    .font(.body).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    .disabled(working || finished)
                VStack {
                    Button("发送") { Task { await send() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(working || finished || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("结束并评分") { Task { await finish() } }
                        .disabled(working || finished || !transcript.contains { $0.role == "user" })
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: 动作

    /// 失败时不清空输入框，用户的草稿原样保留。
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        errorText = nil
        defer { working = false }
        do {
            interviewId = try await model.interviewReply(interviewId: interviewId, message: text)
            draft = ""
            load()
        } catch {
            errorText = userMessage(error)
        }
    }

    private func finish() async {
        guard let id = interviewId else { return }
        working = true
        errorText = nil
        defer { working = false }
        do {
            interview = try await model.finishInterview(id: id)
            loadAverage()
        } catch {
            errorText = userMessage(error)
        }
    }

    private func load() {
        do {
            if let id = interviewId { interview = try model.mockInterview(id: id) }
            loadAverage()
        } catch {
            errorText = userMessage(error)
        }
    }

    private func loadAverage() {
        let scores = ((try? model.mockInterviews()) ?? []).compactMap(\.score).prefix(3)
        recentCount = scores.count
        recentAverage = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }
}
