import Foundation
import NovelAgentCore

struct ReadStorySnapshotTool: AgentTool {
    let definition = LLMToolDefinition(
        name: "read_story_snapshot",
        description: "读取当前小说的故事简报、角色、事实、伏笔、时间线和近期章节摘要",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([:])
        ]),
        accessLevel: .read
    )

    func execute(input: JSONValue, context: AgentToolContext) async throws -> JSONValue {
        let snapshot = try await context.repository.loadSnapshot(projectID: context.projectID)
        return try JSONValue.encoded(snapshot)
    }
}

struct SearchStoryMemoryTool: AgentTool {
    let definition = LLMToolDefinition(
        name: "search_story_memory",
        description: "按关键词检索已写章节的摘要和事实记忆",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("query")]),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object([
                    "type": .string("integer"),
                    "minimum": .number(1),
                    "maximum": .number(30)
                ])
            ])
        ]),
        accessLevel: .read
    )

    func execute(input: JSONValue, context: AgentToolContext) async throws -> JSONValue {
        guard let object = input.objectValue,
              let query = object["query"]?.stringValue
        else {
            throw CoreError.validationFailed(["query 为必填字符串"])
        }
        let limit: Int
        if case let .number(raw) = object["limit"] {
            limit = max(1, min(Int(raw), 30))
        } else {
            limit = 12
        }
        let results = try await context.repository.searchMemory(
            projectID: context.projectID,
            query: query,
            limit: limit
        )
        return try JSONValue.encoded(results)
    }
}
