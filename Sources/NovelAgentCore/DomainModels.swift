import Foundation

public enum ProjectPhase: String, Codable, CaseIterable, Sendable {
    case interviewing
    case choosingDirection
    case planning
    case writing
    case reviewing
}

public enum TargetPlatform: String, Codable, CaseIterable, Sendable {
    case general = "通用网文"
    case fanqie = "番茄"
    case qidian = "起点"
}

public enum QualityPreset: String, Codable, CaseIterable, Sendable {
    case quality = "质量优先"
    case balanced = "均衡"
    case economy = "省钱"
}

public struct StoryProject: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var phase: ProjectPhase
    public var targetPlatform: TargetPlatform
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        phase: ProjectPhase = .interviewing,
        targetPlatform: TargetPlatform = .general,
        revision: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.phase = phase
        self.targetPlatform = targetPlatform
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StoryBrief: Codable, Hashable, Sendable {
    public var genre: String
    public var targetPlatform: TargetPlatform
    public var coreHook: String
    public var protagonist: String
    public var protagonistDesire: String
    public var coreConflict: String
    public var worldRules: String
    public var targetEmotion: String
    public var targetChapterCount: Int
    public var exclusions: String
    public var rawAnswers: [String: String]

    public init(
        genre: String = "",
        targetPlatform: TargetPlatform = .general,
        coreHook: String = "",
        protagonist: String = "",
        protagonistDesire: String = "",
        coreConflict: String = "",
        worldRules: String = "",
        targetEmotion: String = "",
        targetChapterCount: Int = 100,
        exclusions: String = "",
        rawAnswers: [String: String] = [:]
    ) {
        self.genre = genre
        self.targetPlatform = targetPlatform
        self.coreHook = coreHook
        self.protagonist = protagonist
        self.protagonistDesire = protagonistDesire
        self.coreConflict = coreConflict
        self.worldRules = worldRules
        self.targetEmotion = targetEmotion
        self.targetChapterCount = targetChapterCount
        self.exclusions = exclusions
        self.rawAnswers = rawAnswers
    }
}

public struct StoryStage: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var chapterRange: String
    public var objective: String
    public var climax: String
    public var unresolvedQuestion: String

    public init(
        id: UUID = UUID(),
        title: String,
        chapterRange: String,
        objective: String,
        climax: String,
        unresolvedQuestion: String
    ) {
        self.id = id
        self.title = title
        self.chapterRange = chapterRange
        self.objective = objective
        self.climax = climax
        self.unresolvedQuestion = unresolvedQuestion
    }
}

public struct StoryDirection: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var logline: String
    public var positioning: String
    public var protagonistArc: String
    public var coreConflict: String
    public var sellingPoints: [String]
    public var risks: [String]
    public var stages: [StoryStage]

    public init(
        id: UUID = UUID(),
        title: String,
        logline: String,
        positioning: String,
        protagonistArc: String,
        coreConflict: String,
        sellingPoints: [String],
        risks: [String],
        stages: [StoryStage]
    ) {
        self.id = id
        self.title = title
        self.logline = logline
        self.positioning = positioning
        self.protagonistArc = protagonistArc
        self.coreConflict = coreConflict
        self.sellingPoints = sellingPoints
        self.risks = risks
        self.stages = stages
    }
}

public enum OutlineNodeKind: String, Codable, CaseIterable, Sendable {
    case book
    case stage
    case volume
    case chapter
}

public struct OutlineNode: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var parentID: UUID?
    public var kind: OutlineNodeKind
    public var position: Int
    public var title: String
    public var summary: String

    public init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        kind: OutlineNodeKind,
        position: Int,
        title: String,
        summary: String
    ) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.position = position
        self.title = title
        self.summary = summary
    }
}

public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case character
    case faction
    case location
    case item
    case worldRule
}

public struct StoryEntity: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: EntityKind
    public var name: String
    public var summary: String
    public var attributes: [String: String]
    public var knowledge: [String]
    public var revision: Int

    public init(
        id: UUID = UUID(),
        kind: EntityKind,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        knowledge: [String] = [],
        revision: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.attributes = attributes
        self.knowledge = knowledge
        self.revision = revision
    }
}

public struct StoryFact: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var subject: String
    public var predicate: String
    public var object: String
    public var sourceChapter: Int?
    public var confidence: Double

    public init(
        id: UUID = UUID(),
        subject: String,
        predicate: String,
        object: String,
        sourceChapter: Int? = nil,
        confidence: Double = 1
    ) {
        self.id = id
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.sourceChapter = sourceChapter
        self.confidence = confidence
    }
}

public struct StoryRelationship: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var sourceEntityID: UUID
    public var targetEntityID: UUID
    public var kind: String
    public var status: String
    public var sourceChapter: Int?

    public init(
        id: UUID = UUID(),
        sourceEntityID: UUID,
        targetEntityID: UUID,
        kind: String,
        status: String,
        sourceChapter: Int? = nil
    ) {
        self.id = id
        self.sourceEntityID = sourceEntityID
        self.targetEntityID = targetEntityID
        self.kind = kind
        self.status = status
        self.sourceChapter = sourceChapter
    }
}

public enum ForeshadowStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case planted
    case progressing
    case resolved
    case deferred
}

public struct Foreshadow: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var plantedChapter: Int?
    public var expectedResolutionChapter: Int?
    public var resolvedChapter: Int?
    public var status: ForeshadowStatus

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        plantedChapter: Int? = nil,
        expectedResolutionChapter: Int? = nil,
        resolvedChapter: Int? = nil,
        status: ForeshadowStatus = .planned
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.plantedChapter = plantedChapter
        self.expectedResolutionChapter = expectedResolutionChapter
        self.resolvedChapter = resolvedChapter
        self.status = status
    }
}

public struct TimelineEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var order: Int
    public var label: String
    public var detail: String
    public var chapterNumber: Int

    public init(
        id: UUID = UUID(),
        order: Int,
        label: String,
        detail: String,
        chapterNumber: Int
    ) {
        self.id = id
        self.order = order
        self.label = label
        self.detail = detail
        self.chapterNumber = chapterNumber
    }
}

public struct ChapterBeat: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var event: String
    public var emotionalPurpose: String

    public init(
        id: UUID = UUID(),
        label: String,
        event: String,
        emotionalPurpose: String
    ) {
        self.id = id
        self.label = label
        self.event = event
        self.emotionalPurpose = emotionalPurpose
    }
}

public struct ChapterBlueprint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var chapterNumber: Int
    public var provisionalTitle: String
    public var pointOfView: String
    public var setting: String
    public var participantEntityIDs: [UUID]
    public var chapterGoal: String
    public var beats: [ChapterBeat]
    public var mustKeep: [String]
    public var mustAvoid: [String]
    public var activeForeshadowIDs: [UUID]
    public var targetEmotion: String
    public var endingHook: String
    public var targetCharacterCount: Int

    public init(
        id: UUID = UUID(),
        chapterNumber: Int,
        provisionalTitle: String,
        pointOfView: String,
        setting: String,
        participantEntityIDs: [UUID],
        chapterGoal: String,
        beats: [ChapterBeat],
        mustKeep: [String],
        mustAvoid: [String],
        activeForeshadowIDs: [UUID],
        targetEmotion: String,
        endingHook: String,
        targetCharacterCount: Int = 3_000
    ) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.provisionalTitle = provisionalTitle
        self.pointOfView = pointOfView
        self.setting = setting
        self.participantEntityIDs = participantEntityIDs
        self.chapterGoal = chapterGoal
        self.beats = beats
        self.mustKeep = mustKeep
        self.mustAvoid = mustAvoid
        self.activeForeshadowIDs = activeForeshadowIDs
        self.targetEmotion = targetEmotion
        self.endingHook = endingHook
        self.targetCharacterCount = targetCharacterCount
    }
}

public enum ChapterStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case needsReview
    case candidate
}

public struct Chapter: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: Int
    public var title: String
    public var content: String
    public var status: ChapterStatus
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        content: String,
        status: ChapterStatus = .draft,
        revision: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.content = content
        self.status = status
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ChapterSummary: Codable, Hashable, Sendable {
    public var chapterID: UUID
    public var chapterNumber: Int
    public var summary: String
    public var keyEvents: [String]
    public var emotionalShift: String

    public init(
        chapterID: UUID,
        chapterNumber: Int,
        summary: String,
        keyEvents: [String],
        emotionalShift: String
    ) {
        self.chapterID = chapterID
        self.chapterNumber = chapterNumber
        self.summary = summary
        self.keyEvents = keyEvents
        self.emotionalShift = emotionalShift
    }
}

public enum FindingSeverity: String, Codable, CaseIterable, Sendable {
    case s1 = "S1"
    case s2 = "S2"
    case s3 = "S3"
    case s4 = "S4"

    public var blocksCandidate: Bool {
        self == .s1 || self == .s2
    }
}

public enum FindingCategory: String, Codable, CaseIterable, Sendable {
    case structure
    case character
    case prose
    case consistency
    case platform
    case factual
    case format
    case causal
    case ruleBoundary
}

public struct ReviewFinding: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var reviewer: String
    public var severity: FindingSeverity
    public var category: FindingCategory
    public var location: String
    public var evidence: String
    public var issue: String
    public var fix: String

    public init(
        id: UUID = UUID(),
        reviewer: String,
        severity: FindingSeverity,
        category: FindingCategory,
        location: String,
        evidence: String,
        issue: String,
        fix: String
    ) {
        self.id = id
        self.reviewer = reviewer
        self.severity = severity
        self.category = category
        self.location = location
        self.evidence = evidence
        self.issue = issue
        self.fix = fix
    }
}

public struct ReviewReport: Codable, Hashable, Sendable {
    public var verdict: String
    public var findings: [ReviewFinding]
    public var summary: String

    public init(verdict: String, findings: [ReviewFinding], summary: String) {
        self.verdict = verdict
        self.findings = findings
        self.summary = summary
    }
}

public struct CharacterState: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var entityID: UUID
    public var chapterNumber: Int
    public var physicalState: String
    public var emotionalState: String
    public var location: String
    public var resources: [String: Int]
    public var publicImage: String

    public init(
        id: UUID = UUID(),
        entityID: UUID,
        chapterNumber: Int,
        physicalState: String,
        emotionalState: String,
        location: String,
        resources: [String: Int] = [:],
        publicImage: String = ""
    ) {
        self.id = id
        self.entityID = entityID
        self.chapterNumber = chapterNumber
        self.physicalState = physicalState
        self.emotionalState = emotionalState
        self.location = location
        self.resources = resources
        self.publicImage = publicImage
    }
}

public struct MemoryChunk: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: String
    public var content: String
    public var sourceChapter: Int?
    public var keywords: [String]
    public var embedding: [Float]?

    public init(
        id: UUID = UUID(),
        kind: String,
        content: String,
        sourceChapter: Int? = nil,
        keywords: [String] = [],
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.sourceChapter = sourceChapter
        self.keywords = keywords
        self.embedding = embedding
    }
}

public struct StateDelta: Codable, Hashable, Sendable {
    public var expectedProjectRevision: Int
    public var upsertedEntities: [StoryEntity]
    public var upsertedFacts: [StoryFact]
    public var upsertedRelationships: [StoryRelationship]
    public var upsertedForeshadows: [Foreshadow]
    public var timelineEvents: [TimelineEvent]
    public var characterStates: [CharacterState]
    public var resolvedForeshadowIDs: [UUID]

    public init(
        expectedProjectRevision: Int,
        upsertedEntities: [StoryEntity] = [],
        upsertedFacts: [StoryFact] = [],
        upsertedRelationships: [StoryRelationship] = [],
        upsertedForeshadows: [Foreshadow] = [],
        timelineEvents: [TimelineEvent] = [],
        characterStates: [CharacterState] = [],
        resolvedForeshadowIDs: [UUID] = []
    ) {
        self.expectedProjectRevision = expectedProjectRevision
        self.upsertedEntities = upsertedEntities
        self.upsertedFacts = upsertedFacts
        self.upsertedRelationships = upsertedRelationships
        self.upsertedForeshadows = upsertedForeshadows
        self.timelineEvents = timelineEvents
        self.characterStates = characterStates
        self.resolvedForeshadowIDs = resolvedForeshadowIDs
    }
}

public struct BookPlan: Codable, Hashable, Sendable {
    public var title: String
    public var direction: StoryDirection
    public var outline: [OutlineNode]
    public var entities: [StoryEntity]
    public var foreshadows: [Foreshadow]
    public var nextBlueprints: [ChapterBlueprint]

    public init(
        title: String,
        direction: StoryDirection,
        outline: [OutlineNode],
        entities: [StoryEntity],
        foreshadows: [Foreshadow],
        nextBlueprints: [ChapterBlueprint]
    ) {
        self.title = title
        self.direction = direction
        self.outline = outline
        self.entities = entities
        self.foreshadows = foreshadows
        self.nextBlueprints = nextBlueprints
    }
}

public struct StorySnapshot: Codable, Hashable, Sendable {
    public var project: StoryProject
    public var interviewSession: InterviewSession?
    public var brief: StoryBrief?
    public var candidateDirections: [StoryDirection]
    public var selectedDirection: StoryDirection?
    public var outline: [OutlineNode]
    public var entities: [StoryEntity]
    public var facts: [StoryFact]
    public var relationships: [StoryRelationship]
    public var foreshadows: [Foreshadow]
    public var timeline: [TimelineEvent]
    public var characterStates: [CharacterState]
    public var blueprints: [ChapterBlueprint]
    public var recentChapters: [Chapter]
    public var recentSummaries: [ChapterSummary]

    public init(
        project: StoryProject,
        interviewSession: InterviewSession? = nil,
        brief: StoryBrief? = nil,
        candidateDirections: [StoryDirection] = [],
        selectedDirection: StoryDirection? = nil,
        outline: [OutlineNode] = [],
        entities: [StoryEntity] = [],
        facts: [StoryFact] = [],
        relationships: [StoryRelationship] = [],
        foreshadows: [Foreshadow] = [],
        timeline: [TimelineEvent] = [],
        characterStates: [CharacterState] = [],
        blueprints: [ChapterBlueprint] = [],
        recentChapters: [Chapter] = [],
        recentSummaries: [ChapterSummary] = []
    ) {
        self.project = project
        self.interviewSession = interviewSession
        self.brief = brief
        self.candidateDirections = candidateDirections
        self.selectedDirection = selectedDirection
        self.outline = outline
        self.entities = entities
        self.facts = facts
        self.relationships = relationships
        self.foreshadows = foreshadows
        self.timeline = timeline
        self.characterStates = characterStates
        self.blueprints = blueprints
        self.recentChapters = recentChapters
        self.recentSummaries = recentSummaries
    }
}

public struct ChapterCommit: Codable, Hashable, Sendable {
    public var chapter: Chapter
    public var summary: ChapterSummary
    public var stateDelta: StateDelta
    public var findings: [ReviewFinding]
    public var memoryChunks: [MemoryChunk]

    public init(
        chapter: Chapter,
        summary: ChapterSummary,
        stateDelta: StateDelta,
        findings: [ReviewFinding],
        memoryChunks: [MemoryChunk]
    ) {
        self.chapter = chapter
        self.summary = summary
        self.stateDelta = stateDelta
        self.findings = findings
        self.memoryChunks = memoryChunks
    }
}

public struct ProjectArchive: Codable, Hashable, Sendable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var snapshot: StorySnapshot
    public var chapters: [Chapter]
    public var summaries: [ChapterSummary]
    public var reviews: [ReviewFinding]

    public init(
        formatVersion: Int = 1,
        exportedAt: Date = Date(),
        snapshot: StorySnapshot,
        chapters: [Chapter],
        summaries: [ChapterSummary],
        reviews: [ReviewFinding]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.snapshot = snapshot
        self.chapters = chapters
        self.summaries = summaries
        self.reviews = reviews
    }
}
