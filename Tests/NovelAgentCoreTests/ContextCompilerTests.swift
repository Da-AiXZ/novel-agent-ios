import XCTest
@testable import NovelAgentCore

final class ContextCompilerTests: XCTestCase {
    func testCompilerAlwaysIncludesRequiredStateAndTrimsOptionalMemory() throws {
        let entity = StoryEntity(kind: .character, name: "林照", summary: "主角")
        let project = StoryProject(title: "测试书", phase: .writing)
        let brief = StoryBrief(
            genre: "都市",
            coreHook: "倒计时",
            protagonist: "林照"
        )
        let blueprint = ChapterBlueprint(
            chapterNumber: 1,
            provisionalTitle: "倒计时",
            pointOfView: "林照",
            setting: "地铁",
            participantEntityIDs: [entity.id],
            chapterGoal: "发现异常",
            beats: (1 ... 5).map {
                ChapterBeat(label: "\($0)", event: "事件\($0)", emotionalPurpose: "紧张")
            },
            mustKeep: ["倒计时"],
            mustAvoid: ["解释真相"],
            activeForeshadowIDs: [],
            targetEmotion: "紧张",
            endingHook: "数字归零"
        )
        let snapshot = StorySnapshot(
            project: project,
            brief: brief,
            entities: [entity]
        )
        let memories = (0 ..< 100).map {
            MemoryChunk(kind: "fact", content: String(repeating: "很长的记忆\($0)", count: 100))
        }

        let result = try ContextCompiler().compile(
            snapshot: snapshot,
            blueprint: blueprint,
            retrievedMemory: memories,
            budget: ContextBudget(maximumInputTokens: 3_000, reservedOutputTokens: 500)
        )

        XCTAssertTrue(result.rendered.contains("章节蓝图"))
        XCTAssertTrue(result.rendered.contains("故事简报"))
        XCTAssertLessThanOrEqual(result.estimatedTokens, 2_500)
        XCTAssertTrue(result.trace.contains { !$0.included })
    }
}

