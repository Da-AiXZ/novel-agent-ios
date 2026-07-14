import XCTest
import NovelAgentCore
@testable import NovelAgent

final class DatabaseStoryRepositoryTests: XCTestCase {
    func testMigrationAndTransactionalCommit() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "NovelAgent-DBTest-\(UUID().uuidString).sqlite"
        )
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        let database = try AppDatabase(databaseURL: url)
        let repository = DatabaseStoryRepository(database: database)
        let project = StoryProject(title: "数据库测试", phase: .writing)
        try await repository.createProject(project)

        let chapter = Chapter(number: 1, title: "第一章", content: "正文")
        let commit = ChapterCommit(
            chapter: chapter,
            summary: ChapterSummary(
                chapterID: chapter.id,
                chapterNumber: 1,
                summary: "摘要",
                keyEvents: ["事件"],
                emotionalShift: "平静"
            ),
            stateDelta: StateDelta(expectedProjectRevision: 0),
            findings: [],
            memoryChunks: [
                MemoryChunk(kind: "summary", content: "可检索的摘要", sourceChapter: 1)
            ]
        )
        _ = try await repository.apply(
            .commitChapter(commit),
            projectID: project.id,
            expectedRevision: 0
        )

        let chapters = try await repository.listChapters(projectID: project.id)
        let memories = try await repository.searchMemory(
            projectID: project.id,
            query: "可检索",
            limit: 10
        )
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(memories.count, 1)
    }
}
