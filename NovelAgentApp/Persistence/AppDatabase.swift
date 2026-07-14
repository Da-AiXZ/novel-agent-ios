import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    let dbPool: DatabasePool
    let databaseURL: URL

    init(databaseURL: URL? = nil) throws {
        let resolvedURL: URL
        if let databaseURL {
            resolvedURL = databaseURL
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport.appendingPathComponent(
                "NovelAgent",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            resolvedURL = directory.appendingPathComponent("NovelAgent.sqlite")
        }
        self.databaseURL = resolvedURL

        var configuration = Configuration()
        configuration.label = "NovelAgent.Database"
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        dbPool = try DatabasePool(path: resolvedURL.path, configuration: configuration)
        try Self.migrator.migrate(dbPool)
    }

    func backup(to destinationURL: URL) throws {
        try? FileManager.default.removeItem(at: destinationURL)
        let destination = try DatabaseQueue(path: destinationURL.path)
        try dbPool.backup(to: destination)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    phase TEXT NOT NULL,
                    targetPlatform TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 0,
                    interviewJSON TEXT,
                    briefJSON TEXT,
                    directionsJSON TEXT NOT NULL DEFAULT '[]',
                    selectedDirectionJSON TEXT,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE outline_nodes (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    parentID TEXT,
                    kind TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE entities (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    name TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE facts (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    subject TEXT NOT NULL,
                    predicate TEXT NOT NULL,
                    objectValue TEXT NOT NULL,
                    sourceChapter INTEGER,
                    confidence DOUBLE NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE relationships (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    sourceEntityID TEXT NOT NULL,
                    targetEntityID TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    sourceChapter INTEGER,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE foreshadows (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    status TEXT NOT NULL,
                    plantedChapter INTEGER,
                    expectedResolutionChapter INTEGER,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE timeline_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    eventOrder INTEGER NOT NULL,
                    chapterNumber INTEGER NOT NULL,
                    label TEXT NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE chapter_blueprints (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    chapterNumber INTEGER NOT NULL,
                    json TEXT NOT NULL,
                    UNIQUE(projectID, chapterNumber)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE chapters (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    chapterNumber INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    status TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    UNIQUE(projectID, chapterNumber)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE chapter_versions (
                    id TEXT PRIMARY KEY NOT NULL,
                    chapterID TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
                    revision INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    createdAt DATETIME NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE chapter_summaries (
                    chapterID TEXT PRIMARY KEY NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    chapterNumber INTEGER NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE character_states (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    entityID TEXT NOT NULL,
                    chapterNumber INTEGER NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE knowledge_chunks (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    sourceChapter INTEGER,
                    content TEXT NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE knowledge_fts USING fts5(
                    chunkID UNINDEXED,
                    projectID UNINDEXED,
                    content,
                    tokenize = 'unicode61'
                )
                """)

            try db.execute(sql: """
                CREATE TABLE review_findings (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    severity TEXT NOT NULL,
                    category TEXT NOT NULL,
                    location TEXT NOT NULL,
                    json TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE agent_runs (
                    id TEXT PRIMARY KEY NOT NULL,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    currentStep TEXT NOT NULL,
                    expectedProjectRevision INTEGER NOT NULL,
                    payloadJSON TEXT,
                    errorMessage TEXT,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE run_steps (
                    id TEXT PRIMARY KEY NOT NULL,
                    runID TEXT NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,
                    step TEXT NOT NULL,
                    payloadJSON TEXT,
                    createdAt DATETIME NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE model_profiles (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    keyReference TEXT NOT NULL,
                    isActive INTEGER NOT NULL DEFAULT 0,
                    json TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE prompt_templates (
                    id TEXT PRIMARY KEY NOT NULL,
                    role TEXT NOT NULL,
                    version INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    UNIQUE(role, version)
                )
                """)

            try db.execute(sql: "CREATE INDEX idx_outline_project ON outline_nodes(projectID, position)")
            try db.execute(sql: "CREATE INDEX idx_entities_project ON entities(projectID, kind, name)")
            try db.execute(sql: "CREATE INDEX idx_facts_project ON facts(projectID, subject, predicate)")
            try db.execute(sql: "CREATE INDEX idx_timeline_project ON timeline_events(projectID, eventOrder)")
            try db.execute(sql: "CREATE INDEX idx_chapters_project ON chapters(projectID, chapterNumber)")
            try db.execute(sql: "CREATE INDEX idx_states_project ON character_states(projectID, entityID, chapterNumber)")
            try db.execute(sql: "CREATE INDEX idx_runs_project ON agent_runs(projectID, kind, updatedAt)")
        }
        return migrator
    }
}
