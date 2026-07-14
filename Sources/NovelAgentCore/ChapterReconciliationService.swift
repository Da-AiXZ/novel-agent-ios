import Foundation

public struct ChapterStateExtraction: Codable, Hashable, Sendable {
    public var summary: String
    public var keyEvents: [String]
    public var emotionalShift: String
    public var delta: StateDelta
    public var memory: [String]

    public init(
        summary: String,
        keyEvents: [String],
        emotionalShift: String,
        delta: StateDelta,
        memory: [String]
    ) {
        self.summary = summary
        self.keyEvents = keyEvents
        self.emotionalShift = emotionalShift
        self.delta = delta
        self.memory = memory
    }
}

public actor ChapterReconciliationService {
    private let provider: any LLMProvider
    private let repository: any StoryRepository
    private let validator: StateDeltaValidator

    public init(
        provider: any LLMProvider,
        repository: any StoryRepository,
        validator: StateDeltaValidator = .init()
    ) {
        self.provider = provider
        self.repository = repository
        self.validator = validator
    }

    public func reconcile(
        projectID: UUID,
        chapter: Chapter,
        blueprint: ChapterBlueprint,
        model: String
    ) async throws {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        let state = try JSONValue.object([
            "projectRevision": .number(Double(snapshot.project.revision)),
            "entities": .encoded(snapshot.entities),
            "facts": .encoded(snapshot.facts.filter { $0.sourceChapter != chapter.number }),
            "foreshadows": .encoded(snapshot.foreshadows),
            "timeline": .encoded(snapshot.timeline.filter { $0.chapterNumber != chapter.number }),
            "blueprint": .encoded(blueprint)
        ]).jsonString(prettyPrinted: true)
        let request = LLMRequest(
            model: model,
            systemPrompt: PromptLibrary.extractor,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    以下正文由用户手动修改。请重新抽取该章状态。

                    已知状态（已排除本章旧派生记录）：
                    \(state)

                    <chapter_text>
                    \(chapter.content)
                    </chapter_text>
                    """
                )
            ],
            responseSchema: PromptLibrary.extractionSchema,
            maxOutputTokens: 8_000,
            temperature: 0
        )
        var extraction = try await StructuredOutputGenerator.generate(
            provider: provider,
            request: request,
            as: ChapterStateExtraction.self
        )
        extraction.delta.expectedProjectRevision = snapshot.project.revision

        var validationSnapshot = snapshot
        validationSnapshot.facts.removeAll { $0.sourceChapter == chapter.number }
        validationSnapshot.relationships.removeAll { $0.sourceChapter == chapter.number }
        validationSnapshot.timeline.removeAll { $0.chapterNumber == chapter.number }
        validationSnapshot.characterStates.removeAll { $0.chapterNumber == chapter.number }
        try validator.validate(
            extraction.delta,
            against: validationSnapshot,
            chapterNumber: chapter.number
        )

        let summary = ChapterSummary(
            chapterID: chapter.id,
            chapterNumber: chapter.number,
            summary: extraction.summary,
            keyEvents: extraction.keyEvents,
            emotionalShift: extraction.emotionalShift
        )
        _ = try await repository.apply(
            .editChapter(chapter, summary, extraction.delta),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
    }
}

