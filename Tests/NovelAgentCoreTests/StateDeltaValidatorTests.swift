import XCTest
@testable import NovelAgentCore

final class StateDeltaValidatorTests: XCTestCase {
    func testRejectsNegativeResourcesAndStaleRevision() {
        let entity = StoryEntity(kind: .character, name: "林照", summary: "主角")
        let snapshot = StorySnapshot(
            project: StoryProject(title: "测试", phase: .writing, revision: 4),
            entities: [entity]
        )
        let delta = StateDelta(
            expectedProjectRevision: 3,
            characterStates: [
                CharacterState(
                    entityID: entity.id,
                    chapterNumber: 1,
                    physicalState: "正常",
                    emotionalState: "紧张",
                    location: "地铁",
                    resources: ["积分": -1]
                )
            ]
        )

        XCTAssertThrowsError(
            try StateDeltaValidator().validate(delta, against: snapshot, chapterNumber: 1)
        )
    }

    func testAcceptsValidDelta() throws {
        let entity = StoryEntity(kind: .character, name: "林照", summary: "主角")
        let snapshot = StorySnapshot(
            project: StoryProject(title: "测试", phase: .writing, revision: 2),
            entities: [entity]
        )
        let delta = StateDelta(
            expectedProjectRevision: 2,
            timelineEvents: [
                TimelineEvent(order: 0, label: "进入地铁", detail: "林照上车", chapterNumber: 1)
            ],
            characterStates: [
                CharacterState(
                    entityID: entity.id,
                    chapterNumber: 1,
                    physicalState: "正常",
                    emotionalState: "紧张",
                    location: "地铁",
                    resources: ["积分": 0]
                )
            ]
        )
        XCTAssertNoThrow(
            try StateDeltaValidator().validate(delta, against: snapshot, chapterNumber: 1)
        )
    }
}

