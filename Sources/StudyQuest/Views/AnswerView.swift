import StudyCore
import SwiftUI

/// 按作答 id 渲染的作答页：作业、错题重做与（Task 17）考试共用。
/// 作答中显示各题输入并自动保存；交卷后判卷，结果显示在 `ResultView`；考试作答中顶部带倒计时，到点自动交卷。
struct AnswerView: View {
    let model: AppModel
    let attemptId: Int64
    /// 考试不提供提示。
    var showHints = true
    let onClose: () -> Void

    @State private var detail: AttemptDetail?
    @State private var pending = 0
    @State private var answers: [Int64: String] = [:]
    @State private var dirty: Set<Int64> = []
    @State private var saveTasks: [Int64: Task<Void, Never>] = [:]
    /// 每题第一次未保存修改的时间：连续输入时据此保证最长 5 秒存一次。
    @State private var dirtySince: [Int64: Date] = [:]
    @State private var notice: String?
    @State private var hints: [Int64: String] = [:]
    @State private var hintLoading: Int64?
    @State private var hintErrors: [Int64: String] = [:]
    @State private var working = false
    @State private var confirmSubmit = false
    @State private var loadError: String?
    @State private var timeoutFailed = false

    private var answering: Bool { detail?.attempt.status == .inProgress }
    /// 考试一律不给提示，不管调用方传什么。
    private var hintsVisible: Bool { showHints && detail?.attempt.kind != .exam }

    var body: some View {
        VStack(spacing: 0) {
            header
            if answering, detail?.attempt.kind == .exam, let deadline = detail?.attempt.deadline {
                ExamSessionView(deadline: deadline, now: model.now, failed: timeoutFailed,
                                onRetry: { Task { await submit(timedOut: true) } }, onNearExpiry: flushAll) {
                    Task { await submit(timedOut: true) }
                }
            }
            Divider()
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let notice { Label(notice, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                        if answering {
                            ForEach(Array(detail.items.enumerated()), id: \.element.problem.id) { offset, item in
                                problemView(number: offset + 1, item.problem)
                            }
                        } else {
                            ResultView(model: model, detail: detail, pending: pending, regrading: working,
                                       onRegrade: { Task { await regrade() } }, onChanged: reload)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                if answering { Divider(); submitBar(detail) }
            } else {
                ContentUnavailableView(loadError ?? "加载中…", systemImage: "square.and.pencil")
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .onAppear(perform: load)
        .onDisappear(perform: flushAll)
        .onChange(of: answering) { if !answering { confirmSubmit = false } }
        .confirmationDialog("确定交卷？", isPresented: $confirmSubmit) {
            Button("交卷") { Task { await submit() } }
        } message: {
            Text("交卷后不能再修改答案。")
        }
    }

    // MARK: 顶部与底部

    private var header: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Button(answering ? "稍后再做" : "关闭") {
                flushAll()
                if dirty.isEmpty { onClose() } else { notice = Self.unsavedNotice }
            }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var title: String {
        switch detail?.attempt.kind {
        case .assignment: "作业"
        case .mistakeRedo: "错题重做"
        case .exam: "考试"
        case nil: "作答"
        }
    }

    private func submitBar(_ detail: AttemptDetail) -> some View {
        let answered = detail.items.filter { !(answers[$0.problem.id ?? 0] ?? "").isEmpty }.count
        return HStack {
            if working {
                ProgressView().controlSize(.small)
                Text("判卷中…")
            } else {
                Text("已答 \(answered) / \(detail.items.count) 题，答案自动保存").foregroundStyle(.secondary)
            }
            Spacer()
            Button("交卷") { confirmSubmit = true }
                .buttonStyle(.borderedProminent)
                .disabled(working)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: 题目

    private func problemView(number: Int, _ problem: Problem) -> some View {
        let id = problem.id ?? 0
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("第 \(number) 题 · \(kindName(problem.kind))").font(.headline)
                    Spacer()
                    Text("\(Int(problem.maxScore)) 分").foregroundStyle(.secondary)
                }
                Text(problem.prompt).textSelection(.enabled)
                input(for: problem)
                    .disabled(working)
                if hintsVisible {
                    HStack {
                        Button("提示") { Task { await requestHint(problem) } }
                            .disabled(hintLoading != nil || working)
                        if hintLoading == id { ProgressView().controlSize(.small) }
                    }
                    if let hint = hints[id] {
                        Text(hint).textSelection(.enabled).padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if let error = hintErrors[id] { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder private func input(for problem: Problem) -> some View {
        let id = problem.id ?? 0
        switch problem.kind {
        case .singleChoice:
            Picker("", selection: Binding(get: { answers[id] ?? "" }, set: { set(id, $0) })) {
                ForEach(Array(problem.options.enumerated()), id: \.offset) { offset, option in
                    Text(optionText(offset, option)).tag(letter(offset))
                }
            }
            .pickerStyle(.radioGroup).labelsHidden()
        case .multipleChoice:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(problem.options.enumerated()), id: \.offset) { offset, option in
                    Toggle(optionText(offset, option), isOn: Binding(
                        get: { selectedLetters(id).contains(letter(offset)) },
                        set: { on in
                            var chosen = selectedLetters(id)
                            if on { chosen.insert(letter(offset)) } else { chosen.remove(letter(offset)) }
                            set(id, chosen.sorted().joined(separator: ","))
                        }))
                }
            }
        case .shortAnswer:
            TextEditor(text: Binding(get: { answers[id] ?? "" }, set: { set(id, $0) }))
                .font(.body).frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        case .coding, .project:
            CodeEditor(text: Binding(get: { answers[id] ?? "" }, set: { set(id, $0) }), isEditable: answering)
                .frame(minHeight: problem.kind == .coding ? 220 : 280)
        }
    }

    private func kindName(_ kind: ProblemKind) -> String {
        switch kind {
        case .singleChoice: "单选"
        case .multipleChoice: "多选"
        case .shortAnswer: "简答"
        case .coding: "编程"
        case .project: "项目"
        }
    }

    private func letter(_ index: Int) -> String { String(UnicodeScalar(UInt8(65 + index % 26))) }

    private func optionText(_ index: Int, _ option: String) -> String {
        // 选项自带 "A." 之类前缀时不重复加
        let hasLabel = option.range(of: #"^[A-Z][\.．、:：\)）]"#, options: .regularExpression) != nil
        return hasLabel ? option : "\(letter(index)). \(option)"
    }

    private func selectedLetters(_ id: Int64) -> Set<String> {
        Set((answers[id] ?? "").split(separator: ",").map(String.init))
    }

    // MARK: 自动保存（每题防抖 1 秒，连续输入最长 5 秒必存一次）

    private static let debounce: TimeInterval = 1
    private static let maxWait: TimeInterval = 5

    private func set(_ id: Int64, _ value: String) {
        guard answers[id] != value else { return }
        answers[id] = value
        dirty.insert(id)
        let now = model.now()
        let since = dirtySince[id] ?? now
        dirtySince[id] = since
        let delay = min(Self.debounce, max(0, Self.maxWait - now.timeIntervalSince(since)))
        saveTasks[id]?.cancel()
        saveTasks[id] = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            save(id)
        }
    }

    private func save(_ id: Int64) {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        dirtySince[id] = nil
        guard dirty.remove(id) != nil, answering else { return }
        do {
            try model.saveAnswer(attemptId: attemptId, problemId: id, answer: answers[id] ?? "")
        } catch StoreError.blocked(let message) {
            // 时间已到：服务层已自动交卷，停止编辑并显示结果
            notice = message
            dirty.removeAll()
            reload()
        } catch {
            notice = userMessage(error)
            dirty.insert(id)
        }
    }

    private func flushAll() {
        for id in Array(dirty) { save(id) }
        for task in saveTasks.values { task.cancel() }
        saveTasks = [:]
    }

    // MARK: 提示、交卷、判卷

    private func requestHint(_ problem: Problem) async {
        guard let id = problem.id else { return }
        hintLoading = id
        hintErrors[id] = nil
        defer { hintLoading = nil }
        do {
            hints[id] = try await model.hint(problemId: id, currentAnswer: answers[id] ?? "")
        } catch {
            hintErrors[id] = userMessage(error)
        }
    }

    private static let unsavedNotice = "有答案未能保存，请重试"

    /// `timedOut`：考试倒计时到点的自动交卷。保存已被截止时间挡住时不再等待，按已保存的答案交卷。
    private func submit(timedOut: Bool = false) async {
        guard !working else { return }
        // 过了截止时间，手动交卷也按超时处理：之后的保存都会被挡住，不能再等 dirty 清空
        let late = timedOut || (detail?.attempt.deadline.map { model.now() >= $0 } ?? false)
        flushAll()
        guard late || dirty.isEmpty else {
            notice = Self.unsavedNotice
            return
        }
        working = true
        defer { working = false }
        do {
            try await model.submitAndGrade(attemptId: attemptId)
            notice = late ? "时间已到，已自动交卷" : nil
            timeoutFailed = false
        } catch {
            notice = userMessage(error)
            if late { timeoutFailed = true }
        }
        reload()
    }

    private func regrade() async {
        working = true
        defer { working = false }
        await model.regrade(attemptId: attemptId)
        reload()
    }

    // MARK: 加载

    private func load() {
        reload()
        // 已保存的答案作为初始值；之后以本地编辑为准
        for item in detail?.items ?? [] {
            if let id = item.problem.id, answers[id] == nil, let saved = item.answer { answers[id] = saved }
        }
    }

    private func reload() {
        do {
            let loaded = try model.attemptDetail(id: attemptId)
            detail = loaded
            pending = loaded.attempt.status == .inProgress ? 0 : try model.pendingGradingCount(attemptId: attemptId)
            loadError = nil
        } catch {
            loadError = userMessage(error)
        }
    }
}
