import XCTest
@testable import NovelAgentCore

final class InMemoryRepositoryTests: XCTestCase {
    func testRevisionConflictPreventsOverwrite() async throws {
        let repository = InMemoryStoryRepository()
        let project = StoryProject(title: "测试")
        try await repository.createProject(project)
        let brief = StoryBrief(genre: "都市")

        let revision = try await repository.apply(
            .setBrief(brief),
            projectID: project.id,
            expectedRevision: 0
        )
        XCTAssertEqual(revision, 1)

        do {
            _ = try await repository.apply(
                .setBrief(brief),
                projectID: project.id,
                expectedRevision: 0
            )
            XCTFail("Expected stale revision")
        } catch let CoreError.staleRevision(expected, actual) {
            XCTAssertEqual(expected, 0)
            XCTAssertEqual(actual, 1)
        }
    }

    func testEditedChapterReplacesChapterDerivedState() async throws {
        let repository = InMemoryStoryRepository()
        let project = StoryProject(title: "测试", phase: .writing)
        try await repository.createProject(project)
        let chapter = Chapter(number: 1, title: "旧章", content: "旧正文")
        let oldFact = StoryFact(
            subject: "林照",
            predicate: "位置",
            object: "车站",
            sourceChapter: 1
        )
        let commit = ChapterCommit(
            chapter: chapter,
            summary: ChapterSummary(
                chapterID: chapter.id,
                chapterNumber: 1,
                summary: "旧摘要",
                keyEvents: [],
                emotionalShift: ""
            ),
            stateDelta: StateDelta(
                expectedProjectRevision: 0,
                upsertedFacts: [oldFact]
            ),
            findings: [],
            memoryChunks: []
        )
        _ = try await repository.apply(
            .commitChapter(commit),
            projectID: project.id,
            expectedRevision: 0
        )

        var edited = chapter
        edited.content = "新正文"
        edited.revision = 1
        let newFact = StoryFact(
            subject: "林照",
            predicate: "位置",
            object: "地铁",
            sourceChapter: 1
        )
        _ = try await repository.apply(
            .editChapter(
                edited,
                ChapterSummary(
                    chapterID: chapter.id,
                    chapterNumber: 1,
                    summary: "新摘要",
                    keyEvents: [],
                    emotionalShift: ""
                ),
                StateDelta(expectedProjectRevision: 1, upsertedFacts: [newFact])
            ),
            projectID: project.id,
            expectedRevision: 1
        )

        let snapshot = try await repository.loadSnapshot(projectID: project.id)
        XCTAssertFalse(snapshot.facts.contains { $0.object == "车站" })
        XCTAssertTrue(snapshot.facts.contains { $0.object == "地铁" })
    }
}

