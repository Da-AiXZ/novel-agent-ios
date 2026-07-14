import Foundation
import GRDB
import NovelAgentCore

final class DatabaseStoryRepository: StoryRepository, @unchecked Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func listProjects() async throws -> [StoryProject] {
        try await database.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM projects ORDER BY updatedAt DESC"
            )
            return try rows.map(Self.project)
        }
    }

    func createProject(_ project: StoryProject) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO projects
                    (id, title, phase, targetPlatform, revision, directionsJSON, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, '[]', ?, ?)
                    """,
                arguments: [
                    project.id.uuidString,
                    project.title,
                    project.phase.rawValue,
                    project.targetPlatform.rawValue,
                    project.revision,
                    project.createdAt,
                    project.updatedAt
                ]
            )
        }
    }

    func deleteProject(id: UUID) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM knowledge_fts WHERE projectID = ?",
                arguments: [id.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM projects WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func loadSnapshot(projectID: UUID) async throws -> StorySnapshot {
        try await database.dbPool.read { db in
            try Self.snapshot(db: db, projectID: projectID)
        }
    }

    func listChapters(projectID: UUID) async throws -> [Chapter] {
        try await database.dbPool.read { db in
            try Self.chapters(db: db, projectID: projectID)
        }
    }

    func loadChapter(projectID: UUID, chapterID: UUID) async throws -> Chapter {
        try await database.dbPool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM chapters WHERE projectID = ? AND id = ?",
                arguments: [projectID.uuidString, chapterID.uuidString]
            ) else {
                throw CoreError.missingData("章节")
            }
            return try Self.chapter(row)
        }
    }

    func searchMemory(projectID: UUID, query: String, limit: Int) async throws -> [MemoryChunk] {
        try await database.dbPool.read { db in
            let matchQuery = Self.ftsQuery(query)
            var rows: [Row] = []
            if !matchQuery.isEmpty {
                rows = (try? Row.fetchAll(
                    db,
                    sql: """
                        SELECT k.json
                        FROM knowledge_fts
                        JOIN knowledge_chunks k ON k.id = knowledge_fts.chunkID
                        WHERE knowledge_fts.projectID = ?
                          AND knowledge_fts MATCH ?
                        ORDER BY bm25(knowledge_fts)
                        LIMIT ?
                        """,
                    arguments: [projectID.uuidString, matchQuery, limit]
                )) ?? []
            }
            if rows.isEmpty {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT json FROM knowledge_chunks
                        WHERE projectID = ? AND content LIKE ?
                        ORDER BY COALESCE(sourceChapter, 0) DESC
                        LIMIT ?
                        """,
                    arguments: [projectID.uuidString, "%\(query)%", limit]
                )
            }
            return try rows.map { row in
                try Self.decode(row["json"], as: MemoryChunk.self)
            }
        }
    }

    @discardableResult
    func apply(
        _ mutation: StoryMutation,
        projectID: UUID,
        expectedRevision: Int
    ) async throws -> Int {
        try await database.dbPool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT revision FROM projects WHERE id = ?",
                arguments: [projectID.uuidString]
            ) else {
                throw CoreError.missingData("项目")
            }
            let actual: Int = row["revision"]
            guard actual == expectedRevision else {
                throw CoreError.staleRevision(expected: expectedRevision, actual: actual)
            }

            switch mutation {
            case let .saveInterviewSession(session):
                try db.execute(
                    sql: "UPDATE projects SET interviewJSON = ? WHERE id = ?",
                    arguments: [try Self.encode(session), projectID.uuidString]
                )

            case let .setBrief(brief):
                try db.execute(
                    sql: """
                        UPDATE projects
                        SET briefJSON = ?, targetPlatform = ?,
                            phase = CASE WHEN phase = ? THEN ? ELSE phase END
                        WHERE id = ?
                        """,
                    arguments: [
                        try Self.encode(brief),
                        brief.targetPlatform.rawValue,
                        ProjectPhase.interviewing.rawValue,
                        ProjectPhase.choosingDirection.rawValue,
                        projectID.uuidString
                    ]
                )

            case let .setCandidateDirections(directions):
                try db.execute(
                    sql: "UPDATE projects SET directionsJSON = ?, phase = ? WHERE id = ?",
                    arguments: [
                        try Self.encode(directions),
                        ProjectPhase.choosingDirection.rawValue,
                        projectID.uuidString
                    ]
                )

            case let .confirmBookPlan(plan):
                try db.execute(
                    sql: """
                        UPDATE projects
                        SET title = ?, selectedDirectionJSON = ?, phase = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        plan.title,
                        try Self.encode(plan.direction),
                        ProjectPhase.writing.rawValue,
                        projectID.uuidString
                    ]
                )
                try Self.replaceOutline(plan.outline, projectID: projectID, db: db)
                for entity in plan.entities {
                    try Self.upsert(entity, projectID: projectID, db: db)
                }
                for foreshadow in plan.foreshadows {
                    try Self.upsert(foreshadow, projectID: projectID, db: db)
                }
                try Self.upsertBlueprints(plan.nextBlueprints, projectID: projectID, db: db)

            case let .upsertBlueprints(blueprints):
                try Self.upsertBlueprints(blueprints, projectID: projectID, db: db)

            case let .commitChapter(commit):
                try Self.upsert(commit.chapter, projectID: projectID, db: db)
                try Self.upsert(commit.summary, projectID: projectID, db: db)
                for finding in commit.findings {
                    try Self.upsert(finding, projectID: projectID, db: db)
                }
                for chunk in commit.memoryChunks {
                    try Self.upsert(chunk, projectID: projectID, db: db)
                }
                try Self.apply(delta: commit.stateDelta, projectID: projectID, db: db)
                try db.execute(
                    sql: "UPDATE projects SET phase = ? WHERE id = ?",
                    arguments: [ProjectPhase.writing.rawValue, projectID.uuidString]
                )

            case let .editChapter(chapter, summary, delta):
                if let oldRow = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM chapters WHERE projectID = ? AND id = ?",
                    arguments: [projectID.uuidString, chapter.id.uuidString]
                ) {
                    let old = try Self.chapter(oldRow)
                    try db.execute(
                        sql: """
                            INSERT INTO chapter_versions
                            (id, chapterID, revision, title, content, createdAt)
                            VALUES (?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            UUID().uuidString,
                            old.id.uuidString,
                            old.revision,
                            old.title,
                            old.content,
                            Date()
                        ]
                    )
                }
                try Self.upsert(chapter, projectID: projectID, db: db)
                try Self.upsert(summary, projectID: projectID, db: db)
                try Self.removeDerivedState(
                    projectID: projectID,
                    chapterNumber: chapter.number,
                    db: db
                )
                try Self.apply(delta: delta, projectID: projectID, db: db)

            case let .replaceOutline(outline):
                try Self.replaceOutline(outline, projectID: projectID, db: db)
                try db.execute(
                    sql: "DELETE FROM chapter_blueprints WHERE projectID = ?",
                    arguments: [projectID.uuidString]
                )

            case let .deleteChapter(chapterID):
                try db.execute(
                    sql: "DELETE FROM chapters WHERE projectID = ? AND id = ?",
                    arguments: [projectID.uuidString, chapterID.uuidString]
                )
            }

            let newRevision = actual + 1
            try db.execute(
                sql: "UPDATE projects SET revision = ?, updatedAt = ? WHERE id = ?",
                arguments: [newRevision, Date(), projectID.uuidString]
            )
            return newRevision
        }
    }

    func createRun(_ run: AgentRunRecord) async throws {
        try await database.dbPool.write { db in
            try Self.upsert(run, db: db)
        }
    }

    func updateRun(_ run: AgentRunRecord) async throws {
        try await database.dbPool.write { db in
            try Self.upsert(run, db: db)
            try db.execute(
                sql: """
                    INSERT INTO run_steps (id, runID, step, payloadJSON, createdAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    run.id.uuidString,
                    run.currentStep,
                    try run.payload.map { try Self.encode($0) },
                    Date()
                ]
            )
        }
    }

    func loadRecoverableRun(projectID: UUID, kind: String) async throws -> AgentRunRecord? {
        try await database.dbPool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM agent_runs
                    WHERE projectID = ? AND kind = ?
                      AND status IN (?, ?, ?, ?)
                    ORDER BY updatedAt DESC
                    LIMIT 1
                    """,
                arguments: [
                    projectID.uuidString,
                    kind,
                    AgentRunStatus.pending.rawValue,
                    AgentRunStatus.running.rawValue,
                    AgentRunStatus.waitingForUser.rawValue,
                    AgentRunStatus.failed.rawValue
                ]
            ) else {
                return nil
            }
            return try Self.run(row)
        }
    }

    func exportProject(projectID: UUID) async throws -> ProjectArchive {
        try await database.dbPool.read { db in
            let snapshot = try Self.snapshot(db: db, projectID: projectID)
            let chapters = try Self.chapters(db: db, projectID: projectID)
            let summaryRows = try Row.fetchAll(
                db,
                sql: "SELECT json FROM chapter_summaries WHERE projectID = ? ORDER BY chapterNumber",
                arguments: [projectID.uuidString]
            )
            let reviewRows = try Row.fetchAll(
                db,
                sql: "SELECT json FROM review_findings WHERE projectID = ?",
                arguments: [projectID.uuidString]
            )
            return ProjectArchive(
                snapshot: snapshot,
                chapters: chapters,
                summaries: try summaryRows.map { try Self.decode($0["json"], as: ChapterSummary.self) },
                reviews: try reviewRows.map { try Self.decode($0["json"], as: ReviewFinding.self) }
            )
        }
    }

    func restoreProject(_ archive: ProjectArchive) async throws -> UUID {
        guard archive.formatVersion == 1 else {
            throw CoreError.unsupported("备份格式版本 \(archive.formatVersion)")
        }
        return try await database.dbPool.write { db in
            var snapshot = archive.snapshot
            let existing = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM projects WHERE id = ?",
                arguments: [snapshot.project.id.uuidString]
            ) ?? 0
            if existing > 0 {
                try db.execute(
                    sql: "DELETE FROM knowledge_fts WHERE projectID = ?",
                    arguments: [snapshot.project.id.uuidString]
                )
                try db.execute(
                    sql: "DELETE FROM projects WHERE id = ?",
                    arguments: [snapshot.project.id.uuidString]
                )
            }
            snapshot.project.revision += 1
            snapshot.project.updatedAt = Date()
            try Self.insert(snapshot.project, db: db)
            try db.execute(
                sql: """
                    UPDATE projects SET interviewJSON = ?, briefJSON = ?,
                    directionsJSON = ?, selectedDirectionJSON = ? WHERE id = ?
                    """,
                arguments: [
                    try snapshot.interviewSession.map { try Self.encode($0) },
                    try snapshot.brief.map { try Self.encode($0) },
                    try Self.encode(snapshot.candidateDirections),
                    try snapshot.selectedDirection.map { try Self.encode($0) },
                    snapshot.project.id.uuidString
                ]
            )
            try Self.replaceOutline(snapshot.outline, projectID: snapshot.project.id, db: db)
            for entity in snapshot.entities {
                try Self.upsert(entity, projectID: snapshot.project.id, db: db)
            }
            for fact in snapshot.facts {
                try Self.upsert(fact, projectID: snapshot.project.id, db: db)
            }
            for relationship in snapshot.relationships {
                try Self.upsert(relationship, projectID: snapshot.project.id, db: db)
            }
            for foreshadow in snapshot.foreshadows {
                try Self.upsert(foreshadow, projectID: snapshot.project.id, db: db)
            }
            for event in snapshot.timeline {
                try Self.upsert(event, projectID: snapshot.project.id, db: db)
            }
            for state in snapshot.characterStates {
                try Self.upsert(state, projectID: snapshot.project.id, db: db)
            }
            try Self.upsertBlueprints(snapshot.blueprints, projectID: snapshot.project.id, db: db)
            for chapter in archive.chapters {
                try Self.upsert(chapter, projectID: snapshot.project.id, db: db)
            }
            for summary in archive.summaries {
                try Self.upsert(summary, projectID: snapshot.project.id, db: db)
            }
            for finding in archive.reviews {
                try Self.upsert(finding, projectID: snapshot.project.id, db: db)
            }
            return snapshot.project.id
        }
    }

    private static func snapshot(db: Database, projectID: UUID) throws -> StorySnapshot {
        guard let projectRow = try Row.fetchOne(
            db,
            sql: "SELECT * FROM projects WHERE id = ?",
            arguments: [projectID.uuidString]
        ) else {
            throw CoreError.missingData("项目")
        }
        let project = try project(projectRow)
        let interview: InterviewSession? = try optionalDecode(projectRow["interviewJSON"])
        let brief: StoryBrief? = try optionalDecode(projectRow["briefJSON"])
        let directionsRaw: String = projectRow["directionsJSON"]
        let directions: [StoryDirection] =
            try decode(directionsRaw, as: [StoryDirection].self)
        let selected: StoryDirection? = try optionalDecode(projectRow["selectedDirectionJSON"])

        func jsonList<T: Decodable>(_ table: String, order: String = "") throws -> [T] {
            let suffix = order.isEmpty ? "" : " ORDER BY \(order)"
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT json FROM \(table) WHERE projectID = ?\(suffix)",
                arguments: [projectID.uuidString]
            )
            return try rows.map { try decode($0["json"], as: T.self) }
        }

        let recentChapterRows = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM chapters WHERE projectID = ?
                ORDER BY chapterNumber DESC LIMIT 3
                """,
            arguments: [projectID.uuidString]
        )
        let recentSummaryRows = try Row.fetchAll(
            db,
            sql: """
                SELECT json FROM chapter_summaries WHERE projectID = ?
                ORDER BY chapterNumber DESC LIMIT 12
                """,
            arguments: [projectID.uuidString]
        )
        return StorySnapshot(
            project: project,
            interviewSession: interview,
            brief: brief,
            candidateDirections: directions,
            selectedDirection: selected,
            outline: try outline(db: db, projectID: projectID),
            entities: try jsonList("entities", order: "kind, name"),
            facts: try jsonList("facts", order: "COALESCE(sourceChapter, 0)"),
            relationships: try jsonList("relationships"),
            foreshadows: try jsonList("foreshadows", order: "COALESCE(expectedResolutionChapter, 999999)"),
            timeline: try jsonList("timeline_events", order: "eventOrder"),
            characterStates: try jsonList("character_states", order: "chapterNumber"),
            blueprints: try jsonList("chapter_blueprints", order: "chapterNumber"),
            recentChapters: try recentChapterRows.reversed().map { try chapter($0) },
            recentSummaries: try recentSummaryRows.reversed().map {
                try decode($0["json"], as: ChapterSummary.self)
            }
        )
    }

    private static func project(_ row: Row) throws -> StoryProject {
        guard let id = UUID(uuidString: row["id"]),
              let phase = ProjectPhase(rawValue: row["phase"]),
              let platform = TargetPlatform(rawValue: row["targetPlatform"])
        else {
            throw CoreError.validationFailed(["项目记录字段无效"])
        }
        return StoryProject(
            id: id,
            title: row["title"],
            phase: phase,
            targetPlatform: platform,
            revision: row["revision"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"]
        )
    }

    private static func insert(_ project: StoryProject, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO projects
                (id, title, phase, targetPlatform, revision, directionsJSON, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, '[]', ?, ?)
                """,
            arguments: [
                project.id.uuidString,
                project.title,
                project.phase.rawValue,
                project.targetPlatform.rawValue,
                project.revision,
                project.createdAt,
                project.updatedAt
            ]
        )
    }

    private static func chapters(db: Database, projectID: UUID) throws -> [Chapter] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM chapters WHERE projectID = ? ORDER BY chapterNumber",
            arguments: [projectID.uuidString]
        )
        return try rows.map(chapter)
    }

    private static func chapter(_ row: Row) throws -> Chapter {
        guard let id = UUID(uuidString: row["id"]),
              let status = ChapterStatus(rawValue: row["status"])
        else {
            throw CoreError.validationFailed(["章节记录字段无效"])
        }
        return Chapter(
            id: id,
            number: row["chapterNumber"],
            title: row["title"],
            content: row["content"],
            status: status,
            revision: row["revision"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"]
        )
    }

    private static func outline(db: Database, projectID: UUID) throws -> [OutlineNode] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM outline_nodes WHERE projectID = ? ORDER BY position",
            arguments: [projectID.uuidString]
        )
        return try rows.map { row in
            guard let id = UUID(uuidString: row["id"]),
                  let kind = OutlineNodeKind(rawValue: row["kind"])
            else {
                throw CoreError.validationFailed(["大纲节点字段无效"])
            }
            let parentRaw: String? = row["parentID"]
            return OutlineNode(
                id: id,
                parentID: parentRaw.flatMap(UUID.init(uuidString:)),
                kind: kind,
                position: row["position"],
                title: row["title"],
                summary: row["summary"]
            )
        }
    }

    private static func replaceOutline(
        _ outline: [OutlineNode],
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM outline_nodes WHERE projectID = ?",
            arguments: [projectID.uuidString]
        )
        for node in outline {
            try db.execute(
                sql: """
                    INSERT INTO outline_nodes
                    (id, projectID, parentID, kind, position, title, summary)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    node.id.uuidString,
                    projectID.uuidString,
                    node.parentID?.uuidString,
                    node.kind.rawValue,
                    node.position,
                    node.title,
                    node.summary
                ]
            )
        }
    }

    private static func upsertBlueprints(
        _ blueprints: [ChapterBlueprint],
        projectID: UUID,
        db: Database
    ) throws {
        for blueprint in blueprints {
            try db.execute(
                sql: """
                    INSERT INTO chapter_blueprints (id, projectID, chapterNumber, json)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(projectID, chapterNumber) DO UPDATE SET
                        id = excluded.id,
                        json = excluded.json
                    """,
                arguments: [
                    blueprint.id.uuidString,
                    projectID.uuidString,
                    blueprint.chapterNumber,
                    try encode(blueprint)
                ]
            )
        }
    }

    private static func upsert(
        _ entity: StoryEntity,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO entities (id, projectID, kind, name, summary, revision, json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    name = excluded.name,
                    summary = excluded.summary,
                    revision = excluded.revision,
                    json = excluded.json
                """,
            arguments: [
                entity.id.uuidString, projectID.uuidString, entity.kind.rawValue,
                entity.name, entity.summary, entity.revision, try encode(entity)
            ]
        )
    }

    private static func upsert(
        _ fact: StoryFact,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO facts
                (id, projectID, subject, predicate, objectValue, sourceChapter, confidence, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    subject = excluded.subject,
                    predicate = excluded.predicate,
                    objectValue = excluded.objectValue,
                    sourceChapter = excluded.sourceChapter,
                    confidence = excluded.confidence,
                    json = excluded.json
                """,
            arguments: [
                fact.id.uuidString, projectID.uuidString, fact.subject, fact.predicate,
                fact.object, fact.sourceChapter, fact.confidence, try encode(fact)
            ]
        )
    }

    private static func upsert(
        _ relationship: StoryRelationship,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO relationships
                (id, projectID, sourceEntityID, targetEntityID, kind, status, sourceChapter, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    sourceEntityID = excluded.sourceEntityID,
                    targetEntityID = excluded.targetEntityID,
                    kind = excluded.kind,
                    status = excluded.status,
                    sourceChapter = excluded.sourceChapter,
                    json = excluded.json
                """,
            arguments: [
                relationship.id.uuidString, projectID.uuidString,
                relationship.sourceEntityID.uuidString,
                relationship.targetEntityID.uuidString,
                relationship.kind, relationship.status, relationship.sourceChapter,
                try encode(relationship)
            ]
        )
    }

    private static func upsert(
        _ foreshadow: Foreshadow,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO foreshadows
                (id, projectID, title, status, plantedChapter, expectedResolutionChapter, json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    status = excluded.status,
                    plantedChapter = excluded.plantedChapter,
                    expectedResolutionChapter = excluded.expectedResolutionChapter,
                    json = excluded.json
                """,
            arguments: [
                foreshadow.id.uuidString, projectID.uuidString, foreshadow.title,
                foreshadow.status.rawValue, foreshadow.plantedChapter,
                foreshadow.expectedResolutionChapter,
                try encode(foreshadow)
            ]
        )
    }

    private static func upsert(
        _ event: TimelineEvent,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO timeline_events
                (id, projectID, eventOrder, chapterNumber, label, json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    eventOrder = excluded.eventOrder,
                    chapterNumber = excluded.chapterNumber,
                    label = excluded.label,
                    json = excluded.json
                """,
            arguments: [
                event.id.uuidString, projectID.uuidString, event.order,
                event.chapterNumber, event.label, try encode(event)
            ]
        )
    }

    private static func upsert(
        _ state: CharacterState,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO character_states
                (id, projectID, entityID, chapterNumber, json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    entityID = excluded.entityID,
                    chapterNumber = excluded.chapterNumber,
                    json = excluded.json
                """,
            arguments: [
                state.id.uuidString, projectID.uuidString, state.entityID.uuidString,
                state.chapterNumber, try encode(state)
            ]
        )
    }

    private static func upsert(
        _ chapter: Chapter,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO chapters
                (id, projectID, chapterNumber, title, content, status, revision, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(projectID, chapterNumber) DO UPDATE SET
                    id = excluded.id,
                    title = excluded.title,
                    content = excluded.content,
                    status = excluded.status,
                    revision = excluded.revision,
                    updatedAt = excluded.updatedAt
                """,
            arguments: [
                chapter.id.uuidString, projectID.uuidString, chapter.number,
                chapter.title, chapter.content, chapter.status.rawValue,
                chapter.revision, chapter.createdAt, chapter.updatedAt
            ]
        )
    }

    private static func upsert(
        _ summary: ChapterSummary,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO chapter_summaries
                (chapterID, projectID, chapterNumber, json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(chapterID) DO UPDATE SET
                    chapterNumber = excluded.chapterNumber,
                    json = excluded.json
                """,
            arguments: [
                summary.chapterID.uuidString, projectID.uuidString,
                summary.chapterNumber, try encode(summary)
            ]
        )
    }

    private static func upsert(
        _ finding: ReviewFinding,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO review_findings
                (id, projectID, severity, category, location, json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    severity = excluded.severity,
                    category = excluded.category,
                    location = excluded.location,
                    json = excluded.json
                """,
            arguments: [
                finding.id.uuidString, projectID.uuidString,
                finding.severity.rawValue, finding.category.rawValue,
                finding.location, try encode(finding)
            ]
        )
    }

    private static func upsert(
        _ chunk: MemoryChunk,
        projectID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO knowledge_chunks
                (id, projectID, kind, sourceChapter, content, json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    sourceChapter = excluded.sourceChapter,
                    content = excluded.content,
                    json = excluded.json
                """,
            arguments: [
                chunk.id.uuidString, projectID.uuidString, chunk.kind,
                chunk.sourceChapter, chunk.content, try encode(chunk)
            ]
        )
        try db.execute(
            sql: "DELETE FROM knowledge_fts WHERE chunkID = ?",
            arguments: [chunk.id.uuidString]
        )
        try db.execute(
            sql: "INSERT INTO knowledge_fts (chunkID, projectID, content) VALUES (?, ?, ?)",
            arguments: [chunk.id.uuidString, projectID.uuidString, chunk.content]
        )
    }

    private static func apply(
        delta: StateDelta,
        projectID: UUID,
        db: Database
    ) throws {
        for entity in delta.upsertedEntities {
            try upsert(entity, projectID: projectID, db: db)
        }
        for fact in delta.upsertedFacts {
            try upsert(fact, projectID: projectID, db: db)
        }
        for relationship in delta.upsertedRelationships {
            try upsert(relationship, projectID: projectID, db: db)
        }
        for foreshadow in delta.upsertedForeshadows {
            try upsert(foreshadow, projectID: projectID, db: db)
        }
        for event in delta.timelineEvents {
            try upsert(event, projectID: projectID, db: db)
        }
        for state in delta.characterStates {
            try upsert(state, projectID: projectID, db: db)
        }
        for id in delta.resolvedForeshadowIDs {
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT json FROM foreshadows WHERE projectID = ? AND id = ?",
                arguments: [projectID.uuidString, id.uuidString]
            ) else { continue }
            var foreshadow = try decode(row["json"], as: Foreshadow.self)
            foreshadow.status = .resolved
            try upsert(foreshadow, projectID: projectID, db: db)
        }
    }

    private static func removeDerivedState(
        projectID: UUID,
        chapterNumber: Int,
        db: Database
    ) throws {
        let chunkRows = try Row.fetchAll(
            db,
            sql: "SELECT id FROM knowledge_chunks WHERE projectID = ? AND sourceChapter = ?",
            arguments: [projectID.uuidString, chapterNumber]
        )
        for row in chunkRows {
            let id: String = row["id"]
            try db.execute(
                sql: "DELETE FROM knowledge_fts WHERE chunkID = ?",
                arguments: [id]
            )
        }
        try db.execute(
            sql: "DELETE FROM knowledge_chunks WHERE projectID = ? AND sourceChapter = ?",
            arguments: [projectID.uuidString, chapterNumber]
        )
        try db.execute(
            sql: "DELETE FROM facts WHERE projectID = ? AND sourceChapter = ?",
            arguments: [projectID.uuidString, chapterNumber]
        )
        try db.execute(
            sql: "DELETE FROM relationships WHERE projectID = ? AND sourceChapter = ?",
            arguments: [projectID.uuidString, chapterNumber]
        )
        try db.execute(
            sql: "DELETE FROM timeline_events WHERE projectID = ? AND chapterNumber = ?",
            arguments: [projectID.uuidString, chapterNumber]
        )
        try db.execute(
            sql: "DELETE FROM character_states WHERE projectID = ? AND chapterNumber = ?",
            arguments: [projectID.uuidString, chapterNumber]
        )
        try db.execute(
            sql: """
                DELETE FROM foreshadows
                WHERE projectID = ? AND plantedChapter = ? AND status != ?
                """,
            arguments: [
                projectID.uuidString,
                chapterNumber,
                ForeshadowStatus.resolved.rawValue
            ]
        )
    }

    private static func upsert(_ run: AgentRunRecord, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO agent_runs
                (id, projectID, kind, status, currentStep, expectedProjectRevision,
                 payloadJSON, errorMessage, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    status = excluded.status,
                    currentStep = excluded.currentStep,
                    expectedProjectRevision = excluded.expectedProjectRevision,
                    payloadJSON = excluded.payloadJSON,
                    errorMessage = excluded.errorMessage,
                    updatedAt = excluded.updatedAt
                """,
            arguments: [
                run.id.uuidString, run.projectID.uuidString, run.kind,
                run.status.rawValue, run.currentStep, run.expectedProjectRevision,
                try run.payload.map { try encode($0) }, run.errorMessage,
                run.createdAt, run.updatedAt
            ]
        )
    }

    private static func run(_ row: Row) throws -> AgentRunRecord {
        guard let id = UUID(uuidString: row["id"]),
              let projectID = UUID(uuidString: row["projectID"]),
              let status = AgentRunStatus(rawValue: row["status"])
        else {
            throw CoreError.validationFailed(["运行记录字段无效"])
        }
        let payloadRaw: String? = row["payloadJSON"]
        return AgentRunRecord(
            id: id,
            projectID: projectID,
            kind: row["kind"],
            status: status,
            currentStep: row["currentStep"],
            expectedProjectRevision: row["expectedProjectRevision"],
            payload: try payloadRaw.map { try decode($0, as: JSONValue.self) },
            errorMessage: row["errorMessage"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"]
        )
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder.novelAgent.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CoreError.invalidUTF8
        }
        return string
    }

    private static func decode<T: Decodable>(_ value: String, as type: T.Type) throws -> T {
        guard let data = value.data(using: .utf8) else {
            throw CoreError.invalidUTF8
        }
        return try JSONDecoder.novelAgent.decode(type, from: data)
    }

    private static func optionalDecode<T: Decodable>(_ value: String?) throws -> T? {
        guard let value else { return nil }
        return try decode(value, as: T.self)
    }

    private static func ftsQuery(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
    }
}
