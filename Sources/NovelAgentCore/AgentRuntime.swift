import Foundation

public struct AgentToolContext: Sendable {
    public var projectID: UUID
    public var runID: UUID
    public var repository: any StoryRepository

    public init(projectID: UUID, runID: UUID, repository: any StoryRepository) {
        self.projectID = projectID
        self.runID = runID
        self.repository = repository
    }
}

public protocol AgentTool: Sendable {
    var definition: LLMToolDefinition { get }
    func execute(input: JSONValue, context: AgentToolContext) async throws -> JSONValue
}

public enum ToolPermissionDecision: Sendable {
    case allow
    case deny(reason: String)
}

public typealias ToolPermissionHandler = @Sendable (
    _ definition: LLMToolDefinition,
    _ input: JSONValue
) async -> ToolPermissionDecision

public struct AgentRuntimeConfiguration: Sendable {
    public var model: String
    public var systemPrompt: String
    public var maximumTurns: Int
    public var maximumTotalTokens: Int
    public var maximumOutputTokensPerTurn: Int

    public init(
        model: String,
        systemPrompt: String,
        maximumTurns: Int = 8,
        maximumTotalTokens: Int = 80_000,
        maximumOutputTokensPerTurn: Int = 4_096
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.maximumTurns = maximumTurns
        self.maximumTotalTokens = maximumTotalTokens
        self.maximumOutputTokensPerTurn = maximumOutputTokensPerTurn
    }
}

public enum AgentRunEvent: Sendable {
    case started(runID: UUID)
    case textDelta(String)
    case toolRequested(name: String, input: JSONValue)
    case toolCompleted(name: String, output: JSONValue)
    case permissionDenied(name: String, reason: String)
    case usage(LLMUsage)
    case checkpoint(turn: Int)
    case completed(text: String, usage: LLMUsage)
}

public actor AgentRuntime {
    private let provider: any LLMProvider
    private let repository: any StoryRepository
    private let tools: [String: any AgentTool]
    private let permissionHandler: ToolPermissionHandler

    public init(
        provider: any LLMProvider,
        repository: any StoryRepository,
        tools: [any AgentTool],
        permissionHandler: @escaping ToolPermissionHandler = AgentRuntime.defaultPermission
    ) {
        self.provider = provider
        self.repository = repository
        self.tools = Dictionary(
            tools.map { ($0.definition.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.permissionHandler = permissionHandler
    }

    public func run(
        projectID: UUID,
        userMessage: String,
        configuration: AgentRuntimeConfiguration
    ) -> AsyncThrowingStream<AgentRunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.execute(
                        projectID: projectID,
                        userMessage: userMessage,
                        configuration: configuration,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(
        projectID: UUID,
        userMessage: String,
        configuration: AgentRuntimeConfiguration,
        continuation: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        var run = AgentRunRecord(
            projectID: projectID,
            kind: "conversation",
            status: .running,
            currentStep: "query",
            expectedProjectRevision: snapshot.project.revision
        )
        try await repository.createRun(run)
        continuation.yield(.started(runID: run.id))

        var messages = [LLMMessage(role: .user, content: userMessage)]
        var totalUsage = LLMUsage()
        var finalText = ""

        do {
            for turn in 1 ... configuration.maximumTurns {
                try Task.checkCancellation()
                let request = LLMRequest(
                    model: configuration.model,
                    systemPrompt: configuration.systemPrompt,
                    messages: messages,
                    tools: tools.values.map(\.definition),
                    maxOutputTokens: configuration.maximumOutputTokensPerTurn
                )
                let response = try await LLMStreamCollector.collect(
                    provider: provider,
                    request: request,
                    onTextDelta: { continuation.yield(.textDelta($0)) }
                )
                totalUsage = totalUsage + response.usage
                continuation.yield(.usage(response.usage))

                guard totalUsage.inputTokens + totalUsage.outputTokens <= configuration.maximumTotalTokens else {
                    throw CoreError.budgetExceeded
                }

                if response.toolCalls.isEmpty {
                    finalText = response.text
                    run.status = .completed
                    run.currentStep = "completed"
                    run.updatedAt = Date()
                    try await repository.updateRun(run)
                    continuation.yield(.completed(text: finalText, usage: totalUsage))
                    return
                }

                messages.append(
                    LLMMessage(
                        role: .assistant,
                        content: response.text,
                        toolCalls: response.toolCalls
                    )
                )

                for call in response.toolCalls {
                    guard let tool = tools[call.name] else {
                        throw CoreError.missingTool(call.name)
                    }
                    let input = try decodeArguments(call.arguments)
                    continuation.yield(.toolRequested(name: call.name, input: input))
                    switch await permissionHandler(tool.definition, input) {
                    case .allow:
                        let output = try await tool.execute(
                            input: input,
                            context: AgentToolContext(
                                projectID: projectID,
                                runID: run.id,
                                repository: repository
                            )
                        )
                        continuation.yield(.toolCompleted(name: call.name, output: output))
                        messages.append(
                            LLMMessage(
                                role: .tool,
                                content: try output.jsonString(),
                                name: call.name,
                                toolCallID: call.id
                            )
                        )
                    case let .deny(reason):
                        continuation.yield(.permissionDenied(name: call.name, reason: reason))
                        messages.append(
                            LLMMessage(
                                role: .tool,
                                content: #"{"error":"permission_denied"}"#,
                                name: call.name,
                                toolCallID: call.id
                            )
                        )
                    }
                }

                run.currentStep = "turn-\(turn)"
                run.payload = try JSONValue.encoded(messages)
                run.updatedAt = Date()
                try await repository.updateRun(run)
                continuation.yield(.checkpoint(turn: turn))
            }
            throw CoreError.maximumTurnsExceeded
        } catch {
            run.status = error is CancellationError ? .cancelled : .failed
            run.errorMessage = error.localizedDescription
            run.updatedAt = Date()
            try? await repository.updateRun(run)
            throw error
        }
    }

    private func decodeArguments(_ value: String) throws -> JSONValue {
        guard let data = value.data(using: .utf8) else {
            throw CoreError.invalidUTF8
        }
        return try JSONDecoder.novelAgent.decode(JSONValue.self, from: data)
    }

    public static let defaultPermission: ToolPermissionHandler = { definition, _ in
        switch definition.accessLevel {
        case .read, .stageWrite:
            .allow
        case .destructive:
            .deny(reason: "破坏性操作需要由界面单独确认")
        }
    }
}
