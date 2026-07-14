import Foundation

public enum AgentRunStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case waitingForUser
    case completed
    case failed
    case cancelled
}

public struct AgentRunRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var kind: String
    public var status: AgentRunStatus
    public var currentStep: String
    public var expectedProjectRevision: Int
    public var payload: JSONValue?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        kind: String,
        status: AgentRunStatus = .pending,
        currentStep: String = "",
        expectedProjectRevision: Int,
        payload: JSONValue? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.status = status
        self.currentStep = currentStep
        self.expectedProjectRevision = expectedProjectRevision
        self.payload = payload
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum StoryMutation: Sendable {
    case saveInterviewSession(InterviewSession)
    case setBrief(StoryBrief)
    case setCandidateDirections([StoryDirection])
    case confirmBookPlan(BookPlan)
    case upsertBlueprints([ChapterBlueprint])
    case commitChapter(ChapterCommit)
    case editChapter(Chapter, ChapterSummary, StateDelta)
    case replaceOutline([OutlineNode])
    case deleteChapter(UUID)
}

public protocol StoryRepository: Sendable {
    func listProjects() async throws -> [StoryProject]
    func createProject(_ project: StoryProject) async throws
    func deleteProject(id: UUID) async throws
    func loadSnapshot(projectID: UUID) async throws -> StorySnapshot
    func listChapters(projectID: UUID) async throws -> [Chapter]
    func loadChapter(projectID: UUID, chapterID: UUID) async throws -> Chapter
    func searchMemory(projectID: UUID, query: String, limit: Int) async throws -> [MemoryChunk]
    @discardableResult
    func apply(
        _ mutation: StoryMutation,
        projectID: UUID,
        expectedRevision: Int
    ) async throws -> Int
    func createRun(_ run: AgentRunRecord) async throws
    func updateRun(_ run: AgentRunRecord) async throws
    func loadRecoverableRun(projectID: UUID, kind: String) async throws -> AgentRunRecord?
    func exportProject(projectID: UUID) async throws -> ProjectArchive
    func restoreProject(_ archive: ProjectArchive) async throws -> UUID
}

public actor InMemoryStoryRepository: StoryRepository {
    private var snapshots: [UUID: StorySnapshot] = [:]
    private var chapters: [UUID: [Chapter]] = [:]
    private var summaries: [UUID: [ChapterSummary]] = [:]
    private var findings: [UUID: [ReviewFinding]] = [:]
    private var memories: [UUID: [MemoryChunk]] = [:]
    private var runs: [UUID: AgentRunRecord] = [:]

    public init() {}

    public func listProjects() -> [StoryProject] {
        snapshots.values.map(\.project).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func createProject(_ project: StoryProject) throws {
        guard snapshots[project.id] == nil else {
            throw CoreError.validationFailed(["项目 ID 已存在"])
        }
        snapshots[project.id] = StorySnapshot(project: project)
        chapters[project.id] = []
        summaries[project.id] = []
        findings[project.id] = []
        memories[project.id] = []
    }

    public func deleteProject(id: UUID) {
        snapshots.removeValue(forKey: id)
        chapters.removeValue(forKey: id)
        summaries.removeValue(forKey: id)
        findings.removeValue(forKey: id)
        memories.removeValue(forKey: id)
        runs = runs.filter { $0.value.projectID != id }
    }

    public func loadSnapshot(projectID: UUID) throws -> StorySnapshot {
        guard var snapshot = snapshots[projectID] else {
            throw CoreError.missingData("项目")
        }
        snapshot.recentChapters = Array((chapters[projectID] ?? []).suffix(3))
        snapshot.recentSummaries = Array((summaries[projectID] ?? []).suffix(12))
        return snapshot
    }

    public func listChapters(projectID: UUID) -> [Chapter] {
        (chapters[projectID] ?? []).sorted { $0.number < $1.number }
    }

    public func loadChapter(projectID: UUID, chapterID: UUID) throws -> Chapter {
        guard let chapter = chapters[projectID]?.first(where: { $0.id == chapterID }) else {
            throw CoreError.missingData("章节")
        }
        return chapter
    }

    public func searchMemory(projectID: UUID, query: String, limit: Int) -> [MemoryChunk] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return (memories[projectID] ?? [])
            .map { chunk -> (MemoryChunk, Int) in
                let haystack = "\(chunk.content) \(chunk.keywords.joined(separator: " "))".lowercased()
                let score = terms.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
                return (chunk, score)
            }
            .filter { $0.1 > 0 || terms.isEmpty }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    public func apply(
        _ mutation: StoryMutation,
        projectID: UUID,
        expectedRevision: Int
    ) throws -> Int {
        guard var snapshot = snapshots[projectID] else {
            throw CoreError.missingData("项目")
        }
        guard snapshot.project.revision == expectedRevision else {
            throw CoreError.staleRevision(
                expected: expectedRevision,
                actual: snapshot.project.revision
            )
        }

        switch mutation {
        case let .saveInterviewSession(session):
            snapshot.interviewSession = session
        case let .setBrief(brief):
            snapshot.brief = brief
            snapshot.project.targetPlatform = brief.targetPlatform
            if snapshot.project.phase == .interviewing {
                snapshot.project.phase = .choosingDirection
            }
        case let .setCandidateDirections(directions):
            snapshot.candidateDirections = directions
            snapshot.project.phase = .choosingDirection
        case let .confirmBookPlan(plan):
            snapshot.project.title = plan.title
            snapshot.selectedDirection = plan.direction
            snapshot.outline = plan.outline
            snapshot.entities = plan.entities
            snapshot.foreshadows = plan.foreshadows
            snapshot.blueprints = plan.nextBlueprints
            snapshot.project.phase = .writing
        case let .upsertBlueprints(blueprints):
            for blueprint in blueprints {
                snapshot.blueprints.removeAll { $0.id == blueprint.id || $0.chapterNumber == blueprint.chapterNumber }
                snapshot.blueprints.append(blueprint)
            }
            snapshot.blueprints.sort { $0.chapterNumber < $1.chapterNumber }
        case let .commitChapter(commit):
            var projectChapters = chapters[projectID] ?? []
            projectChapters.removeAll { $0.id == commit.chapter.id || $0.number == commit.chapter.number }
            projectChapters.append(commit.chapter)
            chapters[projectID] = projectChapters.sorted { $0.number < $1.number }
            summaries[projectID, default: []].append(commit.summary)
            findings[projectID, default: []].append(contentsOf: commit.findings)
            memories[projectID, default: []].append(contentsOf: commit.memoryChunks)
            apply(delta: commit.stateDelta, to: &snapshot)
            snapshot.project.phase = .writing
        case let .editChapter(chapter, summary, delta):
            guard let index = chapters[projectID]?.firstIndex(where: { $0.id == chapter.id }) else {
                throw CoreError.missingData("章节")
            }
            chapters[projectID]?[index] = chapter
            summaries[projectID]?.removeAll { $0.chapterID == chapter.id }
            summaries[projectID, default: []].append(summary)
            snapshot.facts.removeAll { $0.sourceChapter == chapter.number }
            snapshot.relationships.removeAll { $0.sourceChapter == chapter.number }
            snapshot.timeline.removeAll { $0.chapterNumber == chapter.number }
            snapshot.characterStates.removeAll { $0.chapterNumber == chapter.number }
            snapshot.foreshadows.removeAll {
                $0.plantedChapter == chapter.number && $0.status != .resolved
            }
            memories[projectID]?.removeAll { $0.sourceChapter == chapter.number }
            apply(delta: delta, to: &snapshot)
        case let .replaceOutline(outline):
            snapshot.outline = outline
            snapshot.blueprints.removeAll()
        case let .deleteChapter(chapterID):
            chapters[projectID]?.removeAll { $0.id == chapterID }
            summaries[projectID]?.removeAll { $0.chapterID == chapterID }
            findings[projectID]?.removeAll { $0.location.contains(chapterID.uuidString) }
        }

        snapshot.project.revision += 1
        snapshot.project.updatedAt = Date()
        snapshots[projectID] = snapshot
        return snapshot.project.revision
    }

    public func createRun(_ run: AgentRunRecord) {
        runs[run.id] = run
    }

    public func updateRun(_ run: AgentRunRecord) {
        runs[run.id] = run
    }

    public func loadRecoverableRun(projectID: UUID, kind: String) -> AgentRunRecord? {
        runs.values
            .filter {
                $0.projectID == projectID &&
                $0.kind == kind &&
                [.pending, .running, .waitingForUser, .failed].contains($0.status)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    public func exportProject(projectID: UUID) throws -> ProjectArchive {
        let snapshot = try loadSnapshot(projectID: projectID)
        return ProjectArchive(
            snapshot: snapshot,
            chapters: chapters[projectID] ?? [],
            summaries: summaries[projectID] ?? [],
            reviews: findings[projectID] ?? []
        )
    }

    public func restoreProject(_ archive: ProjectArchive) throws -> UUID {
        guard archive.formatVersion == 1 else {
            throw CoreError.unsupported("备份格式版本 \(archive.formatVersion)")
        }
        var snapshot = archive.snapshot
        let newID = snapshots[snapshot.project.id] == nil ? snapshot.project.id : UUID()
        snapshot.project.id = newID
        snapshot.project.revision += 1
        snapshot.project.updatedAt = Date()
        snapshots[newID] = snapshot
        chapters[newID] = archive.chapters
        summaries[newID] = archive.summaries
        findings[newID] = archive.reviews
        memories[newID] = []
        return newID
    }

    private func apply(delta: StateDelta, to snapshot: inout StorySnapshot) {
        for entity in delta.upsertedEntities {
            snapshot.entities.removeAll { $0.id == entity.id }
            snapshot.entities.append(entity)
        }
        for fact in delta.upsertedFacts {
            snapshot.facts.removeAll { $0.id == fact.id }
            snapshot.facts.append(fact)
        }
        for relationship in delta.upsertedRelationships {
            snapshot.relationships.removeAll { $0.id == relationship.id }
            snapshot.relationships.append(relationship)
        }
        for foreshadow in delta.upsertedForeshadows {
            snapshot.foreshadows.removeAll { $0.id == foreshadow.id }
            snapshot.foreshadows.append(foreshadow)
        }
        for id in delta.resolvedForeshadowIDs {
            guard let index = snapshot.foreshadows.firstIndex(where: { $0.id == id }) else { continue }
            snapshot.foreshadows[index].status = .resolved
        }
        snapshot.timeline.append(contentsOf: delta.timelineEvents)
        snapshot.timeline.sort { $0.order < $1.order }
        snapshot.characterStates.append(contentsOf: delta.characterStates)
    }
}
