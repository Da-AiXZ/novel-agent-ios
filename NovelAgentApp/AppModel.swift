import Foundation
import NovelAgentCore
import NovelAgentProviders

enum AppError: LocalizedError {
    case providerNotConfigured
    case missingAPIKey
    case invalidProject

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            "请先在模型设置中配置一个供应商。"
        case .missingAPIKey:
            "当前模型配置缺少 API Key。"
        case .invalidProject:
            "小说项目不存在或已经被删除。"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var projects: [StoryProject] = []
    @Published private(set) var activeProfile: StoredModelProfile?
    @Published var startupError: String?
    @Published var presentedError: String?
    @Published var isRefreshing = false

    let database: AppDatabase
    let repository: DatabaseStoryRepository
    let profileStore: ModelProfileStore
    let keychain: KeychainStore
    let backupService: ProjectBackupService

    init() {
        let resolvedDatabase: AppDatabase
        var resolvedStartupError: String?
        do {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "NovelAgent-UITests.sqlite"
                )
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + "-wal")
                )
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + "-shm")
                )
                resolvedDatabase = try AppDatabase(databaseURL: url)
            } else {
                resolvedDatabase = try AppDatabase()
            }
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent(
                "NovelAgent-Recovery-\(UUID().uuidString).sqlite"
            )
            do {
                resolvedDatabase = try AppDatabase(databaseURL: fallback)
                resolvedStartupError = "主数据库无法打开，当前使用临时恢复数据库：\(error.localizedDescription)"
            } catch {
                fatalError("NovelAgent database initialization failed: \(error)")
            }
        }
        database = resolvedDatabase
        repository = DatabaseStoryRepository(database: database)
        profileStore = ModelProfileStore(database: database)
        keychain = KeychainStore()
        backupService = ProjectBackupService(repository: repository, database: database)
        startupError = resolvedStartupError
        Task { await refresh() }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let loadedProjects = repository.listProjects()
            let loadedProfile = try profileStore.activeProfile()
            projects = try await loadedProjects
            activeProfile = loadedProfile
        } catch {
            presentedError = error.localizedDescription
        }
    }

    @discardableResult
    func createProject(title: String) async throws -> StoryProject {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = StoryProject(title: normalized.isEmpty ? "未命名小说" : normalized)
        try await repository.createProject(project)
        await refresh()
        return project
    }

    func deleteProject(id: UUID) async throws {
        try await repository.deleteProject(id: id)
        await refresh()
    }

    func snapshot(projectID: UUID) async throws -> StorySnapshot {
        try await repository.loadSnapshot(projectID: projectID)
    }

    func saveInterview(
        projectID: UUID,
        session: InterviewSession
    ) async throws -> StorySnapshot {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        _ = try await repository.apply(
            .saveInterviewSession(session),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
        return try await repository.loadSnapshot(projectID: projectID)
    }

    func completeInterview(
        projectID: UUID,
        session: InterviewSession
    ) async throws -> StorySnapshot {
        let engine = InterviewEngine()
        let brief = engine.buildBrief(from: session)
        var revision = try await repository.loadSnapshot(projectID: projectID).project.revision
        revision = try await repository.apply(
            .saveInterviewSession(session),
            projectID: projectID,
            expectedRevision: revision
        )
        revision = try await repository.apply(
            .setBrief(brief),
            projectID: projectID,
            expectedRevision: revision
        )

        let provider = try makeProvider()
        let routing = try activeRouting()
        let planning = StoryPlanningService(provider: provider)
        let directions = try await planning.generateDirections(brief: brief, routing: routing)
        _ = try await repository.apply(
            .setCandidateDirections(directions),
            projectID: projectID,
            expectedRevision: revision
        )
        await refresh()
        return try await repository.loadSnapshot(projectID: projectID)
    }

    func regenerateDirections(projectID: UUID) async throws -> StorySnapshot {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        guard let brief = snapshot.brief else {
            throw CoreError.missingData("故事简报")
        }
        let planning = StoryPlanningService(provider: try makeProvider())
        let directions = try await planning.generateDirections(
            brief: brief,
            routing: try activeRouting()
        )
        _ = try await repository.apply(
            .setCandidateDirections(directions),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
        return try await repository.loadSnapshot(projectID: projectID)
    }

    func confirmDirection(
        projectID: UUID,
        direction: StoryDirection
    ) async throws -> StorySnapshot {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        guard let brief = snapshot.brief else {
            throw CoreError.missingData("故事简报")
        }
        let planning = StoryPlanningService(provider: try makeProvider())
        let plan = try await planning.buildBookPlan(
            brief: brief,
            direction: direction,
            routing: try activeRouting()
        )
        _ = try await repository.apply(
            .confirmBookPlan(plan),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
        await refresh()
        return try await repository.loadSnapshot(projectID: projectID)
    }

    func planNextChapter(projectID: UUID) async throws -> ChapterBlueprint {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        let planning = StoryPlanningService(provider: try makeProvider())
        let blueprint = try await planning.planNextChapter(
            snapshot: snapshot,
            routing: try activeRouting()
        )
        _ = try await repository.apply(
            .upsertBlueprints([blueprint]),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
        await refresh()
        return blueprint
    }

    func updateBrief(projectID: UUID, brief: StoryBrief) async throws -> StorySnapshot {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        _ = try await repository.apply(
            .setBrief(brief),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
        await refresh()
        return try await repository.loadSnapshot(projectID: projectID)
    }

    func replaceOutline(
        projectID: UUID,
        outline: [OutlineNode]
    ) async throws -> StorySnapshot {
        let snapshot = try await repository.loadSnapshot(projectID: projectID)
        _ = try await repository.apply(
            .replaceOutline(outline),
            projectID: projectID,
            expectedRevision: snapshot.project.revision
        )
        await refresh()
        return try await repository.loadSnapshot(projectID: projectID)
    }

    func reconcileEditedChapter(
        projectID: UUID,
        chapter: Chapter,
        blueprint: ChapterBlueprint
    ) async throws {
        let service = ChapterReconciliationService(
            provider: try makeProvider(),
            repository: repository
        )
        try await service.reconcile(
            projectID: projectID,
            chapter: chapter,
            blueprint: blueprint,
            model: try activeRouting().model(for: .extractor)
        )
        await refresh()
    }

    func exportProject(projectID: UUID) async throws -> URL {
        try await backupService.export(projectID: projectID)
    }

    func restoreProject(from url: URL) async throws -> UUID {
        let id = try await backupService.restore(from: url)
        await refresh()
        return id
    }

    func testProvider(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ProviderProbeResult {
        let provider = try ProviderFactory.make(
            configuration: configuration,
            apiKey: apiKey
        )
        return try await provider.probe(model: configuration.fastModel)
    }

    func saveProfile(
        configuration: ProviderConfiguration,
        apiKey: String
    ) throws {
        let reference = "provider.\(configuration.id.uuidString)"
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedKey.isEmpty {
            guard try keychain.value(for: reference) != nil else {
                throw AppError.missingAPIKey
            }
        } else {
            try keychain.set(normalizedKey, for: reference)
        }
        try profileStore.save(
            configuration: configuration,
            keyReference: reference,
            makeActive: true
        )
        activeProfile = try profileStore.activeProfile()
    }

    func deleteProfile(_ profile: StoredModelProfile) throws {
        try keychain.delete(reference: profile.keyReference)
        try profileStore.delete(id: profile.id)
        activeProfile = try profileStore.activeProfile()
    }

    func makeProvider() throws -> any LLMProvider {
        guard let profile = activeProfile else {
            throw AppError.providerNotConfigured
        }
        guard let key = try keychain.value(for: profile.keyReference), !key.isEmpty else {
            throw AppError.missingAPIKey
        }
        return try ProviderFactory.make(
            configuration: profile.configuration,
            apiKey: key
        )
    }

    func activeRouting() throws -> ModelRouting {
        guard let profile = activeProfile else {
            throw AppError.providerNotConfigured
        }
        return profile.configuration.routing
    }
}
