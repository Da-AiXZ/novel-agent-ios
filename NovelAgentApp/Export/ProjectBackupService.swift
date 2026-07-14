import Foundation
import NovelAgentCore
import ZIPFoundation

struct ProjectBackupManifest: Codable, Sendable {
    var product: String
    var formatVersion: Int
    var projectID: UUID
    var projectTitle: String
    var exportedAt: Date
}

enum BackupError: LocalizedError {
    case invalidPackage
    case missingProjectData

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "这不是有效的 NovelAgent 备份。"
        case .missingProjectData:
            "备份中缺少 project.json。"
        }
    }
}

final class ProjectBackupService: @unchecked Sendable {
    private let repository: any StoryRepository
    private let database: AppDatabase
    private let fileManager: FileManager

    init(
        repository: any StoryRepository,
        database: AppDatabase,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.database = database
        self.fileManager = fileManager
    }

    func export(projectID: UUID) async throws -> URL {
        let archive = try await repository.exportProject(projectID: projectID)
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "NovelAgentExport-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let manifest = ProjectBackupManifest(
            product: "NovelAgent",
            formatVersion: archive.formatVersion,
            projectID: archive.snapshot.project.id,
            projectTitle: archive.snapshot.project.title,
            exportedAt: archive.exportedAt
        )
        try writeJSON(manifest, to: root.appendingPathComponent("manifest.json"))
        try writeJSON(archive, to: root.appendingPathComponent("project.json"))
        try writeText(readme(for: archive), to: root.appendingPathComponent("README.txt"))

        let manuscript = root.appendingPathComponent("正文", isDirectory: true)
        let settings = root.appendingPathComponent("设定", isDirectory: true)
        let outline = root.appendingPathComponent("大纲", isDirectory: true)
        let tracking = root.appendingPathComponent("追踪", isDirectory: true)
        let reviews = root.appendingPathComponent("审查", isDirectory: true)
        for directory in [manuscript, settings, outline, tracking, reviews] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        for chapter in archive.chapters {
            let filename = String(
                format: "第%03d章_%@.md",
                chapter.number,
                safeFilename(chapter.title)
            )
            try writeText(
                "# 第\(chapter.number)章 \(chapter.title)\n\n\(chapter.content)\n",
                to: manuscript.appendingPathComponent(filename)
            )
        }
        if let brief = archive.snapshot.brief {
            try writeText(briefMarkdown(brief), to: settings.appendingPathComponent("故事简报.md"))
        }
        try writeText(
            entitiesMarkdown(archive.snapshot.entities),
            to: settings.appendingPathComponent("实体与角色.md")
        )
        try writeText(
            outlineMarkdown(archive.snapshot.outline),
            to: outline.appendingPathComponent("全书大纲.md")
        )
        try writeText(
            foreshadowMarkdown(archive.snapshot.foreshadows),
            to: tracking.appendingPathComponent("伏笔.md")
        )
        try writeText(
            timelineMarkdown(archive.snapshot.timeline),
            to: tracking.appendingPathComponent("时间线.md")
        )
        try writeJSON(archive.reviews, to: reviews.appendingPathComponent("findings.json"))
        try database.backup(to: root.appendingPathComponent("database.sqlite"))

        let destination = fileManager.temporaryDirectory.appendingPathComponent(
            "\(safeFilename(archive.snapshot.project.title))-NovelAgent-\(dateStamp()).zip"
        )
        try? fileManager.removeItem(at: destination)
        try fileManager.zipItem(
            at: root,
            to: destination,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
        return destination
    }

    func restore(from zipURL: URL) async throws -> UUID {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "NovelAgentRestore-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.unzipItem(at: zipURL, to: root)

        let manifestURL = root.appendingPathComponent("manifest.json")
        let projectURL = root.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BackupError.invalidPackage
        }
        let manifest = try JSONDecoder.novelAgent.decode(
            ProjectBackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.product == "NovelAgent", manifest.formatVersion == 1 else {
            throw BackupError.invalidPackage
        }
        guard fileManager.fileExists(atPath: projectURL.path) else {
            throw BackupError.missingProjectData
        }
        let archive = try JSONDecoder.novelAgent.decode(
            ProjectArchive.self,
            from: Data(contentsOf: projectURL)
        )
        return try await repository.restoreProject(archive)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder.novelAgent(prettyPrinted: true).encode(value).write(
            to: url,
            options: .atomic
        )
    }

    private func writeText(_ value: String, to url: URL) throws {
        guard let data = value.data(using: .utf8) else {
            throw CoreError.invalidUTF8
        }
        try data.write(to: url, options: .atomic)
    }

    private func readme(for archive: ProjectArchive) -> String {
        """
        NovelAgent backup
        Project: \(archive.snapshot.project.title)
        Exported: \(archive.exportedAt.formatted(.iso8601))
        Format: \(archive.formatVersion)

        project.json is the canonical portable backup.
        database.sqlite is an emergency SQLite snapshot.
        API keys are intentionally excluded.
        """
    }

    private func briefMarkdown(_ brief: StoryBrief) -> String {
        """
        # 故事简报

        - 题材：\(brief.genre)
        - 平台：\(brief.targetPlatform.rawValue)
        - 核心梗：\(brief.coreHook)
        - 主角：\(brief.protagonist)
        - 主角欲望：\(brief.protagonistDesire)
        - 核心矛盾：\(brief.coreConflict)
        - 目标情绪：\(brief.targetEmotion)
        - 计划章数：\(brief.targetChapterCount)

        ## 世界规则

        \(brief.worldRules)

        ## 创作禁区

        \(brief.exclusions)
        """
    }

    private func entitiesMarkdown(_ entities: [StoryEntity]) -> String {
        entities.map { entity in
            """
            # \(entity.name)

            - 类型：\(entity.kind.rawValue)
            - 简介：\(entity.summary)
            - 属性：\(entity.attributes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "；"))
            - 已知信息：\(entity.knowledge.joined(separator: "；"))
            """
        }.joined(separator: "\n\n")
    }

    private func outlineMarkdown(_ nodes: [OutlineNode]) -> String {
        nodes.sorted { $0.position < $1.position }.map {
            "\(String(repeating: "#", count: $0.kind == .book ? 1 : 2)) \($0.title)\n\n\($0.summary)"
        }.joined(separator: "\n\n")
    }

    private func foreshadowMarkdown(_ values: [Foreshadow]) -> String {
        let lines = values.map {
            "| \($0.title) | \($0.status.rawValue) | \($0.plantedChapter.map(String.init) ?? "-") | \($0.expectedResolutionChapter.map(String.init) ?? "-") | \($0.detail) |"
        }
        return """
        # 伏笔

        | 标题 | 状态 | 埋设章 | 预计回收 | 内容 |
        | --- | --- | ---: | ---: | --- |
        \(lines.joined(separator: "\n"))
        """
    }

    private func timelineMarkdown(_ values: [TimelineEvent]) -> String {
        values.sorted { $0.order < $1.order }.map {
            "- [\($0.order)] 第\($0.chapterNumber)章 \($0.label)：\($0.detail)"
        }.joined(separator: "\n")
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let parts = value.components(separatedBy: invalid)
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "_")
        let limited = String(joined.prefix(60))
        return limited.isEmpty ? "未命名" : limited
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

