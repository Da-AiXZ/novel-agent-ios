import Foundation

public enum ChapterPipelineStage: String, Codable, CaseIterable, Sendable {
    case preparing
    case compilingContext
    case writing
    case extractingState
    case validatingState
    case reviewing
    case revising
    case committing
    case completed
}

public enum ChapterPipelineEvent: Sendable {
    case started(runID: UUID)
    case stage(ChapterPipelineStage, message: String)
    case contextCompiled(CompiledChapterContext)
    case textDelta(String)
    case draftReady(String)
    case findings([ReviewFinding])
    case checkpoint(ChapterPipelineStage)
    case completed(ChapterCommit)
}

public struct ChapterPipelineConfiguration: Sendable {
    public var contextBudget: ContextBudget
    public var maximumAutomaticRevisions: Int

    public init(
        contextBudget: ContextBudget = .init(),
        maximumAutomaticRevisions: Int = 1
    ) {
        self.contextBudget = contextBudget
        self.maximumAutomaticRevisions = maximumAutomaticRevisions
    }
}

public actor ChapterPipeline {
    private let provider: any LLMProvider
    private let repository: any StoryRepository
    private let compiler: ContextCompiler
    private let validator: StateDeltaValidator

    public init(
        provider: any LLMProvider,
        repository: any StoryRepository,
        compiler: ContextCompiler = .init(),
        validator: StateDeltaValidator = .init()
    ) {
        self.provider = provider
        self.repository = repository
        self.compiler = compiler
        self.validator = validator
    }

    public func run(
        projectID: UUID,
        blueprint: ChapterBlueprint,
        routing: ModelRouting,
        configuration: ChapterPipelineConfiguration = .init(),
        resumeFromCheckpoint: Bool = true
    ) -> AsyncThrowingStream<ChapterPipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.execute(
                        projectID: projectID,
                        blueprint: blueprint,
                        routing: routing,
                        configuration: configuration,
                        resumeFromCheckpoint: resumeFromCheckpoint,
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
        blueprint: ChapterBlueprint,
        routing: ModelRouting,
        configuration: ChapterPipelineConfiguration,
        resumeFromCheckpoint: Bool,
        continuation: AsyncThrowingStream<ChapterPipelineEvent, Error>.Continuation
    ) async throws {
        var snapshot = try await repository.loadSnapshot(projectID: projectID)
        let checkpointAndRun = try await loadOrCreateCheckpoint(
            projectID: projectID,
            snapshot: snapshot,
            resume: resumeFromCheckpoint
        )
        var checkpoint = checkpointAndRun.checkpoint
        var run = checkpointAndRun.run
        continuation.yield(.started(runID: run.id))

        do {
            let memoryQuery = memoryQuery(for: blueprint, snapshot: snapshot)
            let retrieved = try await repository.searchMemory(
                projectID: projectID,
                query: memoryQuery,
                limit: 18
            )
            continuation.yield(.stage(.compilingContext, message: "正在筛选本章需要的事实和记忆"))
            let context = try compiler.compile(
                snapshot: snapshot,
                blueprint: blueprint,
                retrievedMemory: retrieved,
                budget: configuration.contextBudget
            )
            continuation.yield(.contextCompiled(context))
            try await save(
                stage: .compilingContext,
                checkpoint: &checkpoint,
                run: &run
            )

            var draft: String
            if let savedDraft = checkpoint.draft, !savedDraft.isEmpty {
                draft = savedDraft
                continuation.yield(.draftReady(draft))
            } else {
                continuation.yield(.stage(.writing, message: "正文写手正在完成第 \(blueprint.chapterNumber) 章"))
                draft = try await generateDraft(
                    blueprint: blueprint,
                    context: context,
                    model: routing.model(for: .writer),
                    continuation: continuation
                )
                checkpoint.draft = draft
                continuation.yield(.draftReady(draft))
                try await save(stage: .writing, checkpoint: &checkpoint, run: &run)
            }

            var extraction = checkpoint.extraction
            if extraction == nil {
                continuation.yield(.stage(.extractingState, message: "正在提取本章新增事实"))
                extraction = try await extract(
                    draft: draft,
                    blueprint: blueprint,
                    snapshot: snapshot,
                    model: routing.model(for: .extractor)
                )
                extraction?.delta.expectedProjectRevision = snapshot.project.revision
                checkpoint.extraction = extraction
                try await save(stage: .extractingState, checkpoint: &checkpoint, run: &run)
            }

            guard var extraction else {
                throw CoreError.missingData("章节状态增量")
            }
            continuation.yield(.stage(.validatingState, message: "正在校验时间线、角色和资源边界"))
            try validator.validate(
                extraction.delta,
                against: snapshot,
                chapterNumber: blueprint.chapterNumber
            )
            try await save(stage: .validatingState, checkpoint: &checkpoint, run: &run)

            var reviewFindings = checkpoint.findings
            if reviewFindings.isEmpty {
                continuation.yield(.stage(.reviewing, message: "一致性与文字审查正在并行执行"))
                reviewFindings = try await audit(
                    draft: draft,
                    context: context,
                    blueprint: blueprint,
                    routing: routing
                )
                reviewFindings.append(contentsOf: lengthFindings(draft: draft, blueprint: blueprint))
                checkpoint.findings = reviewFindings
                continuation.yield(.findings(reviewFindings))
                try await save(stage: .reviewing, checkpoint: &checkpoint, run: &run)
            }

            if reviewFindings.contains(where: \.severity.blocksCandidate),
               checkpoint.revisionCount < configuration.maximumAutomaticRevisions {
                continuation.yield(.stage(.revising, message: "正在修复本轮必须处理的问题"))
                draft = try await revise(
                    draft: draft,
                    findings: reviewFindings.filter(\.severity.blocksCandidate),
                    blueprint: blueprint,
                    context: context,
                    model: routing.model(for: .reviser),
                    continuation: continuation
                )
                checkpoint.draft = draft
                checkpoint.revisionCount += 1

                extraction = try await extract(
                    draft: draft,
                    blueprint: blueprint,
                    snapshot: snapshot,
                    model: routing.model(for: .extractor)
                )
                extraction.delta.expectedProjectRevision = snapshot.project.revision
                try validator.validate(
                    extraction.delta,
                    against: snapshot,
                    chapterNumber: blueprint.chapterNumber
                )
                reviewFindings = try await audit(
                    draft: draft,
                    context: context,
                    blueprint: blueprint,
                    routing: routing
                )
                reviewFindings.append(contentsOf: lengthFindings(draft: draft, blueprint: blueprint))
                checkpoint.extraction = extraction
                checkpoint.findings = reviewFindings
                continuation.yield(.findings(reviewFindings))
                try await save(stage: .revising, checkpoint: &checkpoint, run: &run)
            }

            snapshot = try await repository.loadSnapshot(projectID: projectID)
            guard snapshot.project.revision == run.expectedProjectRevision else {
                throw CoreError.staleRevision(
                    expected: run.expectedProjectRevision,
                    actual: snapshot.project.revision
                )
            }

            continuation.yield(.stage(.committing, message: "正在以事务方式保存章节和状态"))
            let chapterID = checkpoint.chapterID
            let status: ChapterStatus = reviewFindings.contains(where: \.severity.blocksCandidate)
                ? .needsReview
                : .candidate
            let chapter = Chapter(
                id: chapterID,
                number: blueprint.chapterNumber,
                title: blueprint.provisionalTitle,
                content: draft,
                status: status
            )
            let summary = ChapterSummary(
                chapterID: chapterID,
                chapterNumber: blueprint.chapterNumber,
                summary: extraction.summary,
                keyEvents: extraction.keyEvents,
                emotionalShift: extraction.emotionalShift
            )
            let memory = [
                MemoryChunk(
                    kind: "chapter_summary",
                    content: extraction.summary,
                    sourceChapter: blueprint.chapterNumber,
                    keywords: extraction.keyEvents
                )
            ] + extraction.memory.map {
                MemoryChunk(
                    kind: "chapter_fact",
                    content: $0,
                    sourceChapter: blueprint.chapterNumber
                )
            }
            let commit = ChapterCommit(
                chapter: chapter,
                summary: summary,
                stateDelta: extraction.delta,
                findings: reviewFindings,
                memoryChunks: memory
            )
            _ = try await repository.apply(
                .commitChapter(commit),
                projectID: projectID,
                expectedRevision: run.expectedProjectRevision
            )

            checkpoint.stage = .completed
            run.status = .completed
            run.currentStep = ChapterPipelineStage.completed.rawValue
            run.payload = try JSONValue.encoded(checkpoint)
            run.updatedAt = Date()
            try await repository.updateRun(run)
            continuation.yield(.completed(commit))
        } catch {
            run.status = error is CancellationError ? .cancelled : .failed
            run.errorMessage = error.localizedDescription
            run.updatedAt = Date()
            run.payload = try? JSONValue.encoded(checkpoint)
            try? await repository.updateRun(run)
            throw error
        }
    }

    private func loadOrCreateCheckpoint(
        projectID: UUID,
        snapshot: StorySnapshot,
        resume: Bool
    ) async throws -> (checkpoint: PipelineCheckpoint, run: AgentRunRecord) {
        if resume,
           let existing = try await repository.loadRecoverableRun(
               projectID: projectID,
               kind: "chapter"
           ),
           existing.expectedProjectRevision == snapshot.project.revision,
           let payload = existing.payload,
           let checkpoint = try? payload.decoded(as: PipelineCheckpoint.self) {
            var resumed = existing
            resumed.status = .running
            resumed.errorMessage = nil
            resumed.updatedAt = Date()
            try await repository.updateRun(resumed)
            return (checkpoint, resumed)
        }

        let checkpoint = PipelineCheckpoint(
            stage: .preparing,
            chapterID: UUID(),
            draft: nil,
            extraction: nil,
            findings: [],
            revisionCount: 0
        )
        let run = AgentRunRecord(
            projectID: projectID,
            kind: "chapter",
            status: .running,
            currentStep: ChapterPipelineStage.preparing.rawValue,
            expectedProjectRevision: snapshot.project.revision,
            payload: try JSONValue.encoded(checkpoint)
        )
        try await repository.createRun(run)
        return (checkpoint, run)
    }

    private func save(
        stage: ChapterPipelineStage,
        checkpoint: inout PipelineCheckpoint,
        run: inout AgentRunRecord
    ) async throws {
        checkpoint.stage = stage
        run.currentStep = stage.rawValue
        run.payload = try JSONValue.encoded(checkpoint)
        run.updatedAt = Date()
        try await repository.updateRun(run)
    }

    private func generateDraft(
        blueprint: ChapterBlueprint,
        context: CompiledChapterContext,
        model: String,
        continuation: AsyncThrowingStream<ChapterPipelineEvent, Error>.Continuation
    ) async throws -> String {
        let request = LLMRequest(
            model: model,
            systemPrompt: PromptLibrary.writer,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    按以下编译上下文写第 \(blueprint.chapterNumber) 章正文。
                    目标字数：\(blueprint.targetCharacterCount) 个中文字符左右。

                    \(context.rendered)
                    """
                )
            ],
            maxOutputTokens: max(4_096, blueprint.targetCharacterCount * 2),
            temperature: 0.8
        )
        let response = try await LLMStreamCollector.collect(
            provider: provider,
            request: request,
            onTextDelta: { continuation.yield(.textDelta($0)) }
        )
        let draft = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            throw ProviderError.invalidResponse("正文为空")
        }
        return draft
    }

    private func extract(
        draft: String,
        blueprint: ChapterBlueprint,
        snapshot: StorySnapshot,
        model: String
    ) async throws -> ExtractionPayload {
        let knownState = try JSONValue.object([
            "projectRevision": .number(Double(snapshot.project.revision)),
            "entities": .encoded(snapshot.entities),
            "facts": .encoded(snapshot.facts),
            "foreshadows": .encoded(snapshot.foreshadows),
            "timeline": .encoded(Array(snapshot.timeline.suffix(50))),
            "blueprint": .encoded(blueprint)
        ]).jsonString(prettyPrinted: true)
        let request = LLMRequest(
            model: model,
            systemPrompt: PromptLibrary.extractor,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    已知状态：
                    \(knownState)

                    本章正文：
                    <chapter_text>
                    \(draft)
                    </chapter_text>
                    """
                )
            ],
            responseSchema: PromptLibrary.extractionSchema,
            maxOutputTokens: 8_000,
            temperature: 0
        )
        return try await StructuredOutputGenerator.generate(
            provider: provider,
            request: request,
            as: ExtractionPayload.self
        )
    }

    private func audit(
        draft: String,
        context: CompiledChapterContext,
        blueprint: ChapterBlueprint,
        routing: ModelRouting
    ) async throws -> [ReviewFinding] {
        async let consistency = review(
            reviewer: "consistency-auditor",
            systemPrompt: PromptLibrary.consistencyAuditor,
            draft: draft,
            context: context,
            blueprint: blueprint,
            model: routing.model(for: .consistencyAuditor)
        )
        async let prose = review(
            reviewer: "prose-auditor",
            systemPrompt: PromptLibrary.proseAuditor,
            draft: draft,
            context: context,
            blueprint: blueprint,
            model: routing.model(for: .proseAuditor)
        )
        let (consistencyReport, proseReport) = try await (consistency, prose)
        return consistencyReport.findings + proseReport.findings
    }

    private func review(
        reviewer: String,
        systemPrompt: String,
        draft: String,
        context: CompiledChapterContext,
        blueprint: ChapterBlueprint,
        model: String
    ) async throws -> ReviewReport {
        let request = LLMRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    章节蓝图：
                    \(try JSONValue.encoded(blueprint).jsonString(prettyPrinted: true))

                    事实与上下文：
                    \(context.rendered)

                    待审正文：
                    <chapter_text>
                    \(draft)
                    </chapter_text>
                    """
                )
            ],
            responseSchema: PromptLibrary.reviewSchema,
            maxOutputTokens: 5_000,
            temperature: 0
        )
        let payload = try await StructuredOutputGenerator.generate(
            provider: provider,
            request: request,
            as: ReviewPayload.self
        )
        return payload.domainModel(reviewer: reviewer)
    }

    private func revise(
        draft: String,
        findings: [ReviewFinding],
        blueprint: ChapterBlueprint,
        context: CompiledChapterContext,
        model: String,
        continuation: AsyncThrowingStream<ChapterPipelineEvent, Error>.Continuation
    ) async throws -> String {
        let findingsJSON = try JSONValue.encoded(findings).jsonString(prettyPrinted: true)
        let request = LLMRequest(
            model: model,
            systemPrompt: PromptLibrary.reviser,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    章节蓝图与事实：
                    \(context.rendered)

                    必须修复的问题：
                    \(findingsJSON)

                    原正文：
                    <chapter_text>
                    \(draft)
                    </chapter_text>
                    """
                )
            ],
            maxOutputTokens: max(4_096, blueprint.targetCharacterCount * 2),
            temperature: 0.5
        )
        let response = try await LLMStreamCollector.collect(
            provider: provider,
            request: request,
            onTextDelta: { continuation.yield(.textDelta($0)) }
        )
        let revised = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revised.isEmpty else {
            throw ProviderError.invalidResponse("修订正文为空")
        }
        return revised
    }

    private func lengthFindings(
        draft: String,
        blueprint: ChapterBlueprint
    ) -> [ReviewFinding] {
        let count = draft.filter { !$0.isWhitespace && !$0.isNewline }.count
        let lower = Int(Double(blueprint.targetCharacterCount) * 0.9)
        let upper = Int(Double(blueprint.targetCharacterCount) * 1.1)
        guard count < lower || count > upper else { return [] }
        return [
            ReviewFinding(
                reviewer: "length-validator",
                severity: .s2,
                category: .format,
                location: "全文",
                evidence: "当前 \(count) 字，目标区间 \(lower)-\(upper) 字",
                issue: count < lower ? "章节明显低于目标字数" : "章节明显超过目标字数",
                fix: count < lower
                    ? "只扩展蓝图内已有冲突、对话和选择代价"
                    : "压缩过场与重复说明，不删除核心事件"
            )
        ]
    }

    private func memoryQuery(
        for blueprint: ChapterBlueprint,
        snapshot: StorySnapshot
    ) -> String {
        let entityNames = snapshot.entities
            .filter { blueprint.participantEntityIDs.contains($0.id) }
            .map(\.name)
        let foreshadowNames = snapshot.foreshadows
            .filter { blueprint.activeForeshadowIDs.contains($0.id) }
            .map(\.title)
        return ([blueprint.chapterGoal, blueprint.targetEmotion] + entityNames + foreshadowNames)
            .joined(separator: " ")
    }
}

private struct PipelineCheckpoint: Codable, Sendable {
    var stage: ChapterPipelineStage
    var chapterID: UUID
    var draft: String?
    var extraction: ExtractionPayload?
    var findings: [ReviewFinding]
    var revisionCount: Int
}

private struct ExtractionPayload: Codable, Sendable {
    var summary: String
    var keyEvents: [String]
    var emotionalShift: String
    var delta: StateDelta
    var memory: [String]
}

private struct ReviewPayload: Codable, Sendable {
    var verdict: String
    var summary: String
    var findings: [FindingPayload]

    func domainModel(reviewer: String) -> ReviewReport {
        ReviewReport(
            verdict: verdict,
            findings: findings.map { $0.domainModel(reviewer: reviewer) },
            summary: summary
        )
    }
}

private struct FindingPayload: Codable, Sendable {
    var severity: String
    var category: String
    var location: String
    var evidence: String
    var issue: String
    var fix: String

    func domainModel(reviewer: String) -> ReviewFinding {
        ReviewFinding(
            reviewer: reviewer,
            severity: FindingSeverity(rawValue: severity) ?? .s3,
            category: FindingCategory(rawValue: category) ?? .prose,
            location: location,
            evidence: evidence,
            issue: issue,
            fix: fix
        )
    }
}

