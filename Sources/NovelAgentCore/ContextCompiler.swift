import Foundation

public struct ContextBudget: Codable, Hashable, Sendable {
    public var maximumInputTokens: Int
    public var reservedOutputTokens: Int

    public init(maximumInputTokens: Int = 48_000, reservedOutputTokens: Int = 8_000) {
        self.maximumInputTokens = maximumInputTokens
        self.reservedOutputTokens = reservedOutputTokens
    }

    public var usableInputTokens: Int {
        max(2_000, maximumInputTokens - reservedOutputTokens)
    }
}

public struct ContextTraceEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var estimatedTokens: Int
    public var included: Bool
    public var reason: String

    public init(
        id: UUID = UUID(),
        name: String,
        estimatedTokens: Int,
        included: Bool,
        reason: String
    ) {
        self.id = id
        self.name = name
        self.estimatedTokens = estimatedTokens
        self.included = included
        self.reason = reason
    }
}

public struct CompiledChapterContext: Codable, Hashable, Sendable {
    public var rendered: String
    public var estimatedTokens: Int
    public var trace: [ContextTraceEntry]

    public init(rendered: String, estimatedTokens: Int, trace: [ContextTraceEntry]) {
        self.rendered = rendered
        self.estimatedTokens = estimatedTokens
        self.trace = trace
    }
}

public struct ContextCompiler: Sendable {
    public init() {}

    public func compile(
        snapshot: StorySnapshot,
        blueprint: ChapterBlueprint,
        retrievedMemory: [MemoryChunk],
        budget: ContextBudget
    ) throws -> CompiledChapterContext {
        var trace: [ContextTraceEntry] = []
        var sections: [String] = []
        var consumed = 0

        func appendRequired<T: Encodable>(_ name: String, _ value: T) throws {
            let content = try render(name: name, value: value)
            let tokens = estimateTokens(content)
            sections.append(content)
            consumed += tokens
            trace.append(
                ContextTraceEntry(
                    name: name,
                    estimatedTokens: tokens,
                    included: true,
                    reason: "生产链必需"
                )
            )
        }

        func appendOptional<T: Encodable>(_ name: String, _ value: T, reason: String) throws {
            let content = try render(name: name, value: value)
            let tokens = estimateTokens(content)
            let included = consumed + tokens <= budget.usableInputTokens
            if included {
                sections.append(content)
                consumed += tokens
            }
            trace.append(
                ContextTraceEntry(
                    name: name,
                    estimatedTokens: tokens,
                    included: included,
                    reason: included ? reason : "超出上下文预算"
                )
            )
        }

        try appendRequired("章节蓝图", blueprint)
        try appendRequired("项目", snapshot.project)
        if let brief = snapshot.brief {
            try appendRequired("故事简报", brief)
        }
        if let direction = snapshot.selectedDirection {
            try appendRequired("确认方向", direction)
        }

        let participants = snapshot.entities.filter {
            blueprint.participantEntityIDs.contains($0.id)
        }
        try appendRequired("本章角色与实体", participants)

        let activeForeshadows = snapshot.foreshadows.filter {
            blueprint.activeForeshadowIDs.contains($0.id) ||
            [.planted, .progressing].contains($0.status)
        }
        try appendRequired("活跃伏笔", activeForeshadows)

        let relevantStates = snapshot.characterStates.filter {
            blueprint.participantEntityIDs.contains($0.entityID)
        }
        try appendOptional("角色当前状态", relevantStates, reason: "参与角色状态")
        try appendOptional("世界事实", snapshot.facts, reason: "事实一致性")
        try appendOptional("人物关系", snapshot.relationships, reason: "关系连续性")
        try appendOptional("最近时间线", Array(snapshot.timeline.suffix(40)), reason: "时序连续性")
        try appendOptional("最近章节摘要", snapshot.recentSummaries, reason: "长程承接")
        try appendOptional("上一章正文", snapshot.recentChapters.last, reason: "语言与场景承接")
        try appendOptional("检索记忆", retrievedMemory, reason: "与本章目标相关")

        guard consumed <= budget.usableInputTokens else {
            throw CoreError.validationFailed(["必要上下文超过模型预算"])
        }
        return CompiledChapterContext(
            rendered: sections.joined(separator: "\n\n"),
            estimatedTokens: consumed,
            trace: trace
        )
    }

    public func estimateTokens(_ text: String) -> Int {
        let scalarCount = text.unicodeScalars.count
        let asciiCount = text.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 0) }
        let nonASCII = scalarCount - asciiCount
        return max(1, Int(ceil(Double(asciiCount) / 4.0 + Double(nonASCII) * 0.8)))
    }

    private func render<T: Encodable>(name: String, value: T) throws -> String {
        let data = try JSONEncoder.novelAgent(prettyPrinted: true).encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CoreError.invalidUTF8
        }
        return "## \(name)\n\(json)"
    }
}

