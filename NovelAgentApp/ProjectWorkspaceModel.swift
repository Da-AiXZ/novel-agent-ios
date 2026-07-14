import Foundation
import NovelAgentCore

struct WorkspaceChatMessage: Identifiable, Hashable {
    enum Sender: Hashable {
        case user
        case agent
    }

    var id = UUID()
    var sender: Sender
    var content: String
}

@MainActor
final class ProjectWorkspaceModel: ObservableObject {
    @Published private(set) var snapshot: StorySnapshot?
    @Published private(set) var chapters: [Chapter] = []
    @Published var streamingText = ""
    @Published var stageMessage = ""
    @Published var findings: [ReviewFinding] = []
    @Published var chatMessages: [WorkspaceChatMessage] = []
    @Published var chatInput = ""
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var exportURL: URL?

    let projectID: UUID
    private unowned let appModel: AppModel
    private var operationTask: Task<Void, Never>?
    private var chatTask: Task<Void, Never>?

    init(projectID: UUID, appModel: AppModel) {
        self.projectID = projectID
        self.appModel = appModel
    }

    var nextChapterNumber: Int {
        (chapters.map(\.number).max() ?? 0) + 1
    }

    var nextBlueprint: ChapterBlueprint? {
        snapshot?.blueprints.first(where: { $0.chapterNumber == nextChapterNumber })
    }

    var primaryActionTitle: String {
        nextBlueprint == nil ? "细化下一章" : "写下一章"
    }

    func load() async {
        do {
            async let loadedSnapshot = appModel.repository.loadSnapshot(projectID: projectID)
            async let loadedChapters = appModel.repository.listChapters(projectID: projectID)
            snapshot = try await loadedSnapshot
            chapters = try await loadedChapters
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performPrimaryAction() {
        guard !isWorking else { return }
        if nextBlueprint == nil {
            planNext()
        } else {
            writeNext()
        }
    }

    func planNext() {
        guard !isWorking else { return }
        isWorking = true
        stageMessage = "正在细化下一章"
        operationTask = Task {
            defer { isWorking = false }
            do {
                _ = try await appModel.planNextChapter(projectID: projectID)
                await load()
                stageMessage = "章节蓝图已准备"
            } catch is CancellationError {
                stageMessage = "已取消"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func writeNext() {
        guard !isWorking, let blueprint = nextBlueprint else { return }
        isWorking = true
        streamingText = ""
        findings = []
        stageMessage = "准备章节"
        operationTask = Task {
            defer { isWorking = false }
            do {
                let pipeline = ChapterPipeline(
                    provider: try appModel.makeProvider(),
                    repository: appModel.repository
                )
                let stream = await pipeline.run(
                    projectID: projectID,
                    blueprint: blueprint,
                    routing: try appModel.activeRouting()
                )
                for try await event in stream {
                    switch event {
                    case .started:
                        stageMessage = "生产任务已启动"
                    case let .stage(_, message):
                        stageMessage = message
                    case .contextCompiled:
                        break
                    case let .textDelta(delta):
                        streamingText += delta
                    case let .draftReady(draft):
                        streamingText = draft
                    case let .findings(values):
                        findings = values
                    case let .checkpoint(stage):
                        stageMessage = "已保存检查点：\(stage.rawValue)"
                    case .completed:
                        stageMessage = "章节已保存"
                        await load()
                        await appModel.refresh()
                    }
                }
            } catch is CancellationError {
                stageMessage = "已取消，已完成步骤可从检查点恢复"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
    }

    func sendChat() {
        let input = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, chatTask == nil else { return }
        chatInput = ""
        chatMessages.append(WorkspaceChatMessage(sender: .user, content: input))
        let responseID = UUID()
        chatMessages.append(
            WorkspaceChatMessage(id: responseID, sender: .agent, content: "")
        )

        chatTask = Task {
            defer { chatTask = nil }
            do {
                let runtime = AgentRuntime(
                    provider: try appModel.makeProvider(),
                    repository: appModel.repository,
                    tools: [ReadStorySnapshotTool(), SearchStoryMemoryTool()]
                )
                let routing = try appModel.activeRouting()
                let stream = await runtime.run(
                    projectID: projectID,
                    userMessage: input,
                    configuration: AgentRuntimeConfiguration(
                        model: routing.model(for: .chapterPlanner),
                        systemPrompt: """
                        你是当前小说的统一创作 Agent。回答项目信息前必须先读取事实源；
                        需要回忆远处章节时使用记忆检索。不要把猜测说成已确认事实。
                        用户提出修改时只分析影响并给出建议，不直接覆盖已确认设定。
                        """
                    )
                )
                for try await event in stream {
                    switch event {
                    case let .textDelta(delta):
                        append(delta, to: responseID)
                    case let .completed(text, _):
                        if chatMessages.first(where: { $0.id == responseID })?.content.isEmpty == true {
                            replace(messageID: responseID, with: text)
                        }
                    default:
                        break
                    }
                }
            } catch {
                replace(messageID: responseID, with: "请求失败：\(error.localizedDescription)")
            }
        }
    }

    func export() {
        guard !isWorking else { return }
        isWorking = true
        operationTask = Task {
            defer { isWorking = false }
            do {
                exportURL = try await appModel.exportProject(projectID: projectID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func append(_ text: String, to messageID: UUID) {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageID }) else { return }
        chatMessages[index].content += text
    }

    private func replace(messageID: UUID, with text: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageID }) else { return }
        chatMessages[index].content = text
    }
}
