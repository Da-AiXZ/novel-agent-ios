import Foundation

public struct StateDeltaValidator: Sendable {
    public init() {}

    public func validate(
        _ delta: StateDelta,
        against snapshot: StorySnapshot,
        chapterNumber: Int
    ) throws {
        var errors: [String] = []
        if delta.expectedProjectRevision != snapshot.project.revision {
            errors.append(
                "状态增量版本 \(delta.expectedProjectRevision) 与项目版本 \(snapshot.project.revision) 不一致"
            )
        }

        validateUniqueIDs(delta.upsertedEntities.map(\.id), label: "实体", errors: &errors)
        validateUniqueIDs(delta.upsertedFacts.map(\.id), label: "事实", errors: &errors)
        validateUniqueIDs(delta.timelineEvents.map(\.id), label: "时间事件", errors: &errors)
        validateUniqueIDs(delta.characterStates.map(\.id), label: "角色状态", errors: &errors)

        let entityIDs = Set(snapshot.entities.map(\.id) + delta.upsertedEntities.map(\.id))
        for relationship in delta.upsertedRelationships {
            if !entityIDs.contains(relationship.sourceEntityID) {
                errors.append("关系来源实体不存在：\(relationship.sourceEntityID)")
            }
            if !entityIDs.contains(relationship.targetEntityID) {
                errors.append("关系目标实体不存在：\(relationship.targetEntityID)")
            }
        }
        for state in delta.characterStates {
            if !entityIDs.contains(state.entityID) {
                errors.append("角色状态引用了未知实体：\(state.entityID)")
            }
            if state.chapterNumber != chapterNumber {
                errors.append("角色状态章节号必须为 \(chapterNumber)")
            }
            if state.resources.values.contains(where: { $0 < 0 }) {
                errors.append("角色资源不能为负数：\(state.entityID)")
            }
        }

        let knownForeshadows = Set(
            snapshot.foreshadows.map(\.id) + delta.upsertedForeshadows.map(\.id)
        )
        for id in delta.resolvedForeshadowIDs where !knownForeshadows.contains(id) {
            errors.append("尝试回收未知伏笔：\(id)")
        }

        let maximumTimelineOrder = snapshot.timeline.map(\.order).max() ?? -1
        for event in delta.timelineEvents {
            if event.order < maximumTimelineOrder {
                errors.append("时间线 order 倒退：\(event.order) < \(maximumTimelineOrder)")
            }
            if event.chapterNumber != chapterNumber {
                errors.append("时间事件章节号必须为 \(chapterNumber)")
            }
        }

        let strongExistingFacts = Dictionary(
            grouping: snapshot.facts.filter { $0.confidence >= 0.8 },
            by: { "\($0.subject)|\($0.predicate)" }
        )
        for fact in delta.upsertedFacts where fact.confidence >= 0.8 {
            let key = "\(fact.subject)|\(fact.predicate)"
            if let existing = strongExistingFacts[key],
               existing.contains(where: { $0.object != fact.object }) {
                errors.append("事实可能冲突：\(fact.subject) / \(fact.predicate)")
            }
        }

        guard errors.isEmpty else {
            throw CoreError.validationFailed(errors)
        }
    }

    private func validateUniqueIDs(
        _ ids: [UUID],
        label: String,
        errors: inout [String]
    ) {
        if Set(ids).count != ids.count {
            errors.append("\(label)增量包含重复 ID")
        }
    }
}

