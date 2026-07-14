import SwiftUI
import NovelAgentCore

struct InterviewFlowView: View {
    @EnvironmentObject private var appModel: AppModel
    let snapshot: StorySnapshot
    let onUpdated: (StorySnapshot) -> Void

    @State private var session: InterviewSession
    @State private var answer = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showingProviderSettings = false

    private let engine = InterviewEngine()

    init(snapshot: StorySnapshot, onUpdated: @escaping (StorySnapshot) -> Void) {
        self.snapshot = snapshot
        self.onUpdated = onUpdated
        _session = State(
            initialValue: snapshot.interviewSession ?? InterviewSession(projectID: snapshot.project.id)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(
                value: Double(session.currentQuestionIndex),
                total: Double(InterviewEngine.questions.count)
            )
            .tint(AppTheme.accent)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(completedQuestions, id: \.question.id) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.question.prompt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.answer)
                                .font(.body)
                                .padding(10)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if let question = engine.currentQuestion(for: session) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(question.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(question.prompt)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            if !question.options.isEmpty {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(question.options, id: \.self) { option in
                                        Button(option) { answer = option }
                                            .buttonStyle(.bordered)
                                            .tint(answer == option ? AppTheme.accent : .secondary)
                                    }
                                }
                            }
                            TextEditor(text: $answer)
                                .frame(minHeight: 96)
                                .padding(6)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                                .accessibilityIdentifier("interviewAnswer")
                        }
                    }
                }
                .padding(16)
            }

            VStack(spacing: 8) {
                PrimaryActionButton(
                    title: isLastQuestion ? "生成三个开书方向" : "继续",
                    systemImage: isLastQuestion ? "sparkles" : "arrow.right",
                    isBusy: isBusy,
                    disabled: answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    submit()
                }
                if session.currentQuestionIndex > 0 && !isBusy {
                    Button {
                        goBack()
                    } label: {
                        Label("上一题", systemImage: "arrow.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.bar)
        }
        .navigationTitle(snapshot.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProviderSettings) {
            NavigationStack {
                ProviderSettingsView()
                    .environmentObject(appModel)
            }
        }
        .alert(
            "无法继续",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            if appModel.activeProfile == nil {
                Button("配置模型") { showingProviderSettings = true }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var completedQuestions: [(question: InterviewQuestion, answer: String)] {
        InterviewEngine.questions.prefix(session.currentQuestionIndex).compactMap { question in
            guard let answer = session.answers[question.id], !answer.isEmpty else { return nil }
            return (question, answer)
        }
    }

    private var isLastQuestion: Bool {
        session.currentQuestionIndex == InterviewEngine.questions.count - 1
    }

    private func submit() {
        guard !isBusy else { return }
        if isLastQuestion, appModel.activeProfile == nil {
            errorMessage = AppError.providerNotConfigured.localizedDescription
            return
        }
        let next = engine.answer(answer, session: session)
        session = next
        answer = ""
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if next.currentQuestionIndex >= InterviewEngine.questions.count {
                    onUpdated(
                        try await appModel.completeInterview(
                            projectID: snapshot.project.id,
                            session: next
                        )
                    )
                } else {
                    onUpdated(
                        try await appModel.saveInterview(
                            projectID: snapshot.project.id,
                            session: next
                        )
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func goBack() {
        let previous = engine.moveBack(session: session)
        session = previous
        answer = engine.currentQuestion(for: previous).flatMap {
            previous.answers[$0.id]
        } ?? ""
        Task {
            _ = try? await appModel.saveInterview(
                projectID: snapshot.project.id,
                session: previous
            )
        }
    }
}
