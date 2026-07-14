import Foundation
import XCTest
@testable import NovelAgentCore

final class ChapterPipelineTests: XCTestCase {
    func testPipelineCommitsCandidateChapter() async throws {
        let repository = InMemoryStoryRepository()
        let entity = StoryEntity(kind: .character, name: "林照", summary: "主角")
        let project = StoryProject(title: "测试", phase: .writing)
        try await repository.createProject(project)
        let direction = StoryDirection(
            title: "倒计时",
            logline: "林照看见死亡倒计时",
            positioning: "都市悬疑",
            protagonistArc: "从逃避到承担",
            coreConflict: "倒计时来源",
            sellingPoints: ["倒计时"],
            risks: [],
            stages: []
        )
        let blueprint = ChapterBlueprint(
            chapterNumber: 1,
            provisionalTitle: "三十秒",
            pointOfView: "林照",
            setting: "地铁",
            participantEntityIDs: [entity.id],
            chapterGoal: "发现倒计时",
            beats: (1 ... 5).map {
                ChapterBeat(label: "\($0)", event: "推进事件\($0)", emotionalPurpose: "紧张")
            },
            mustKeep: ["倒计时"],
            mustAvoid: ["解释来源"],
            activeForeshadowIDs: [],
            targetEmotion: "紧张",
            endingHook: "归零",
            targetCharacterCount: 1_500
        )
        _ = try await repository.apply(
            .confirmBookPlan(
                BookPlan(
                    title: "倒计时",
                    direction: direction,
                    outline: [],
                    entities: [entity],
                    foreshadows: [],
                    nextBlueprints: [blueprint]
                )
            ),
            projectID: project.id,
            expectedRevision: 0
        )

        let provider = ScriptedProvider { request in
            switch request.responseSchema?.name {
            case "chapter_state_delta":
                let extraction = ChapterStateExtraction(
                    summary: "林照在地铁看见倒计时。",
                    keyEvents: ["看见倒计时"],
                    emotionalShift: "平静到紧张",
                    delta: StateDelta(expectedProjectRevision: 1),
                    memory: ["林照第一次看见倒计时"]
                )
                return [.textDelta(try! Self.json(extraction)), .completed]
            case "chapter_review":
                return [
                    .textDelta(
                        #"{"verdict":"APPROVE","summary":"通过","findings":[]}"#
                    ),
                    .completed
                ]
            default:
                return [
                    .textDelta(String(repeating: "他盯着倒计时，车门正要关闭。", count: 100)),
                    .completed
                ]
            }
        }
        let pipeline = ChapterPipeline(provider: provider, repository: repository)
        let stream = await pipeline.run(
            projectID: project.id,
            blueprint: blueprint,
            routing: ModelRouting(strongModel: "strong", fastModel: "fast")
        )

        var completed: ChapterCommit?
        for try await event in stream {
            if case let .completed(commit) = event {
                completed = commit
            }
        }
        XCTAssertEqual(completed?.chapter.status, .candidate)
        let chapters = await repository.listChapters(projectID: project.id)
        let finalSnapshot = try await repository.loadSnapshot(projectID: project.id)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(finalSnapshot.project.revision, 2)
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder.novelAgent.encode(value), encoding: .utf8)!
    }
}

private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    let providerID = "scripted"
    let capabilities = ProviderCapabilities(
        supportsStreaming: true,
        supportsTools: true,
        supportsStrictJSONSchema: true
    )
    private let handler: @Sendable (LLMRequest) -> [LLMEvent]

    init(handler: @escaping @Sendable (LLMRequest) -> [LLMEvent]) {
        self.handler = handler
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        let events = handler(request)
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func probe(model: String) async throws -> ProviderProbeResult {
        ProviderProbeResult(capabilities: capabilities, latencyMilliseconds: 1, message: "OK")
    }

    func embed(texts: [String], model: String) async throws -> [[Float]] {
        texts.map { _ in [0, 1] }
    }
}
