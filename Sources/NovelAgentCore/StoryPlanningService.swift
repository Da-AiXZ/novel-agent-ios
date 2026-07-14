import Foundation

public struct ModelRouting: Codable, Hashable, Sendable {
    public var preset: QualityPreset
    public var strongModel: String
    public var fastModel: String
    public var embeddingModel: String?

    public init(
        preset: QualityPreset = .quality,
        strongModel: String,
        fastModel: String,
        embeddingModel: String? = nil
    ) {
        self.preset = preset
        self.strongModel = strongModel
        self.fastModel = fastModel
        self.embeddingModel = embeddingModel
    }

    public func model(for role: AgentRole) -> String {
        switch (preset, role) {
        case (.quality, .interviewDirector),
             (.quality, .architect),
             (.quality, .chapterPlanner),
             (.quality, .writer),
             (.quality, .reviser):
            strongModel
        case (.economy, _):
            fastModel
        case (_, .extractor),
             (_, .consistencyAuditor),
             (_, .proseAuditor):
            fastModel
        default:
            strongModel
        }
    }
}

public enum AgentRole: String, Codable, CaseIterable, Sendable {
    case interviewDirector
    case architect
    case chapterPlanner
    case writer
    case extractor
    case consistencyAuditor
    case proseAuditor
    case reviser
}

public actor StoryPlanningService {
    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    public func generateDirections(
        brief: StoryBrief,
        routing: ModelRouting
    ) async throws -> [StoryDirection] {
        let briefJSON = try JSONValue.encoded(brief).jsonString(prettyPrinted: true)
        let request = LLMRequest(
            model: routing.model(for: .interviewDirector),
            systemPrompt: PromptLibrary.interviewDirector,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    根据以下故事简报生成三个候选方向：
                    \(briefJSON)
                    """
                )
            ],
            responseSchema: PromptLibrary.directionSchema,
            maxOutputTokens: 6_000,
            temperature: 0.8
        )
        let envelope = try await StructuredOutputGenerator.generate(
            provider: provider,
            request: request,
            as: DirectionEnvelope.self
        )
        guard envelope.directions.count == 3 else {
            throw CoreError.validationFailed(["候选方向必须正好为三个"])
        }
        return envelope.directions.map(\.domainModel)
    }

    public func buildBookPlan(
        brief: StoryBrief,
        direction: StoryDirection,
        routing: ModelRouting
    ) async throws -> BookPlan {
        let input = try JSONValue.object([
            "brief": .encoded(brief),
            "direction": .encoded(direction)
        ]).jsonString(prettyPrinted: true)
        let request = LLMRequest(
            model: routing.model(for: .architect),
            systemPrompt: PromptLibrary.architect,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    为已确认方向建立开书计划。未来三章必须从第 1 章开始。
                    \(input)
                    """
                )
            ],
            responseSchema: PromptLibrary.bookPlanSchema,
            maxOutputTokens: 10_000,
            temperature: 0.5
        )
        let payload = try await StructuredOutputGenerator.generate(
            provider: provider,
            request: request,
            as: BookPlanPayload.self
        )
        return try payload.domainModel(direction: direction)
    }

    public func planNextChapter(
        snapshot: StorySnapshot,
        routing: ModelRouting
    ) async throws -> ChapterBlueprint {
        let nextNumber = (snapshot.recentChapters.map(\.number).max() ?? 0) + 1
        let planningInput = PlanningSnapshot(
            project: snapshot.project,
            brief: snapshot.brief,
            selectedDirection: snapshot.selectedDirection,
            outline: snapshot.outline,
            entities: snapshot.entities,
            foreshadows: snapshot.foreshadows,
            facts: snapshot.facts,
            recentSummaries: snapshot.recentSummaries,
            nextChapterNumber: nextNumber
        )
        let input = try JSONValue.encoded(planningInput).jsonString(prettyPrinted: true)
        let request = LLMRequest(
            model: routing.model(for: .chapterPlanner),
            systemPrompt: PromptLibrary.chapterPlanner,
            messages: [
                LLMMessage(
                    role: .user,
                    content: """
                    为第 \(nextNumber) 章生成蓝图。参与角色和活跃伏笔必须使用输入中的名称。
                    \(input)
                    """
                )
            ],
            responseSchema: PromptLibrary.blueprintSchema,
            maxOutputTokens: 4_000,
            temperature: 0.4
        )
        let payload = try await StructuredOutputGenerator.generate(
            provider: provider,
            request: request,
            as: BlueprintPayload.self
        )
        guard payload.chapterNumber == nextNumber else {
            throw CoreError.validationFailed(["蓝图章节号必须为 \(nextNumber)"])
        }
        return try payload.domainModel(
            entityIDsByName: try Self.uniqueLookup(
                snapshot.entities.map { ($0.name, $0.id) },
                label: "实体名称"
            ),
            foreshadowIDsByTitle: try Self.uniqueLookup(
                snapshot.foreshadows.map { ($0.title, $0.id) },
                label: "伏笔标题"
            )
        )
    }

    private static func uniqueLookup(
        _ pairs: [(String, UUID)],
        label: String
    ) throws -> [String: UUID] {
        var result: [String: UUID] = [:]
        for (key, value) in pairs {
            guard result[key] == nil else {
                throw CoreError.validationFailed(["\(label)重复：\(key)"])
            }
            result[key] = value
        }
        return result
    }
}

private struct PlanningSnapshot: Codable, Sendable {
    var project: StoryProject
    var brief: StoryBrief?
    var selectedDirection: StoryDirection?
    var outline: [OutlineNode]
    var entities: [StoryEntity]
    var foreshadows: [Foreshadow]
    var facts: [StoryFact]
    var recentSummaries: [ChapterSummary]
    var nextChapterNumber: Int
}

private struct DirectionEnvelope: Codable, Sendable {
    var directions: [DirectionPayload]
}

private struct DirectionPayload: Codable, Sendable {
    var title: String
    var logline: String
    var positioning: String
    var protagonistArc: String
    var coreConflict: String
    var sellingPoints: [String]
    var risks: [String]
    var stages: [StagePayload]

    var domainModel: StoryDirection {
        StoryDirection(
            title: title,
            logline: logline,
            positioning: positioning,
            protagonistArc: protagonistArc,
            coreConflict: coreConflict,
            sellingPoints: sellingPoints,
            risks: risks,
            stages: stages.map(\.domainModel)
        )
    }
}

private struct StagePayload: Codable, Sendable {
    var title: String
    var chapterRange: String
    var objective: String
    var climax: String
    var unresolvedQuestion: String

    var domainModel: StoryStage {
        StoryStage(
            title: title,
            chapterRange: chapterRange,
            objective: objective,
            climax: climax,
            unresolvedQuestion: unresolvedQuestion
        )
    }
}

private struct BookPlanPayload: Codable, Sendable {
    var title: String
    var outline: [OutlinePayload]
    var entities: [EntityPayload]
    var foreshadows: [ForeshadowPayload]
    var blueprints: [BlueprintPayload]

    func domainModel(direction: StoryDirection) throws -> BookPlan {
        let domainEntities = entities.map(\.domainModel)
        guard Set(domainEntities.map(\.name)).count == domainEntities.count else {
            throw CoreError.validationFailed(["开书计划包含重名实体"])
        }
        let entityIDs = Dictionary(
            uniqueKeysWithValues: domainEntities.map { ($0.name, $0.id) }
        )
        let domainForeshadows = foreshadows.map(\.domainModel)
        guard Set(domainForeshadows.map(\.title)).count == domainForeshadows.count else {
            throw CoreError.validationFailed(["开书计划包含重名伏笔"])
        }
        let foreshadowIDs = Dictionary(
            uniqueKeysWithValues: domainForeshadows.map { ($0.title, $0.id) }
        )

        var nodes = outline.map {
            OutlineNode(
                kind: OutlineNodeKind(rawValue: $0.kind) ?? .stage,
                position: $0.position,
                title: $0.title,
                summary: $0.summary
            )
        }
        guard Set(nodes.map(\.title)).count == nodes.count else {
            throw CoreError.validationFailed(["大纲节点标题重复"])
        }
        let nodeIDsByTitle = Dictionary(uniqueKeysWithValues: nodes.map { ($0.title, $0.id) })
        for index in nodes.indices {
            if let parentTitle = outline[index].parentTitle {
                guard let parentID = nodeIDsByTitle[parentTitle] else {
                    throw CoreError.validationFailed(["大纲父节点不存在：\(parentTitle)"])
                }
                nodes[index].parentID = parentID
            }
        }

        let domainBlueprints = try blueprints.map {
            try $0.domainModel(
                entityIDsByName: entityIDs,
                foreshadowIDsByTitle: foreshadowIDs
            )
        }
        let expectedNumbers = [1, 2, 3]
        guard domainBlueprints.map(\.chapterNumber).sorted() == expectedNumbers else {
            throw CoreError.validationFailed(["开书计划必须提供第 1-3 章蓝图"])
        }

        return BookPlan(
            title: title,
            direction: direction,
            outline: nodes.sorted { $0.position < $1.position },
            entities: domainEntities,
            foreshadows: domainForeshadows,
            nextBlueprints: domainBlueprints.sorted { $0.chapterNumber < $1.chapterNumber }
        )
    }
}

private struct OutlinePayload: Codable, Sendable {
    var kind: String
    var position: Int
    var title: String
    var summary: String
    var parentTitle: String?
}

private struct EntityPayload: Codable, Sendable {
    var kind: String
    var name: String
    var summary: String
    var attributes: [String: String]
    var knowledge: [String]

    var domainModel: StoryEntity {
        StoryEntity(
            kind: EntityKind(rawValue: kind) ?? .character,
            name: name,
            summary: summary,
            attributes: attributes,
            knowledge: knowledge
        )
    }
}

private struct ForeshadowPayload: Codable, Sendable {
    var title: String
    var detail: String
    var expectedResolutionChapter: Int?

    var domainModel: Foreshadow {
        Foreshadow(
            title: title,
            detail: detail,
            expectedResolutionChapter: expectedResolutionChapter,
            status: .planned
        )
    }
}

private struct BeatPayload: Codable, Sendable {
    var label: String
    var event: String
    var emotionalPurpose: String

    var domainModel: ChapterBeat {
        ChapterBeat(label: label, event: event, emotionalPurpose: emotionalPurpose)
    }
}

private struct BlueprintPayload: Codable, Sendable {
    var chapterNumber: Int
    var provisionalTitle: String
    var pointOfView: String
    var setting: String
    var participants: [String]
    var chapterGoal: String
    var beats: [BeatPayload]
    var mustKeep: [String]
    var mustAvoid: [String]
    var activeForeshadows: [String]
    var targetEmotion: String
    var endingHook: String
    var targetCharacterCount: Int

    func domainModel(
        entityIDsByName: [String: UUID],
        foreshadowIDsByTitle: [String: UUID]
    ) throws -> ChapterBlueprint {
        guard beats.count == 5 else {
            throw CoreError.validationFailed(["章节蓝图必须包含五个节拍"])
        }
        let missingEntities = participants.filter { entityIDsByName[$0] == nil }
        guard missingEntities.isEmpty else {
            throw CoreError.validationFailed(["蓝图引用未知角色：\(missingEntities.joined(separator: "、"))"])
        }
        let missingForeshadows = activeForeshadows.filter { foreshadowIDsByTitle[$0] == nil }
        guard missingForeshadows.isEmpty else {
            throw CoreError.validationFailed(["蓝图引用未知伏笔：\(missingForeshadows.joined(separator: "、"))"])
        }
        return ChapterBlueprint(
            chapterNumber: chapterNumber,
            provisionalTitle: provisionalTitle,
            pointOfView: pointOfView,
            setting: setting,
            participantEntityIDs: participants.compactMap { entityIDsByName[$0] },
            chapterGoal: chapterGoal,
            beats: beats.map(\.domainModel),
            mustKeep: mustKeep,
            mustAvoid: mustAvoid,
            activeForeshadowIDs: activeForeshadows.compactMap { foreshadowIDsByTitle[$0] },
            targetEmotion: targetEmotion,
            endingHook: endingHook,
            targetCharacterCount: max(1_500, min(targetCharacterCount, 8_000))
        )
    }
}
