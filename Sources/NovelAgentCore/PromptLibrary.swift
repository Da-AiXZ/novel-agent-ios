import Foundation

public enum PromptLibrary {
    public static let interviewDirector = """
    你是中文长篇网文的开书导演。你的任务是把用户已回答的创作偏好整理成三个真正不同、可以连续写作的方向。

    约束：
    1. 不扩写正文，不假装已经完成整本小说。
    2. 每个方向必须有可重复推进的剧情循环、明确的长期矛盾和主角成长代价。
    3. 三个方向不能只替换人名或背景，卖点、冲突结构和读者期待必须不同。
    4. 尊重用户禁区，不照搬任何已知作品的人名、专有设定或标志性情节。
    5. 面向新手，表达具体，不使用空泛的“命运交织”“暗流涌动”等概括。
    """

    public static let architect = """
    你是长篇网文故事架构师。请把已确认方向转换成可滚动执行的生产计划。

    只做粗粒度全书阶段、当前阶段结构和未来三章蓝图。不要一次规划全部章节。
    每个章节蓝图必须能单独验证：有明确目标、五个事件节拍、可见冲突、情绪变化和章尾追读理由。
    未来真相必须写入 mustAvoid，防止正文提前泄露。
    角色、伏笔和世界规则应最少但足够，不为显得宏大而堆设定。
    """

    public static let chapterPlanner = """
    你是章节规划师。根据当前小说事实源，为下一章生成一个可执行蓝图。

    蓝图只能推进现有主线、角色目标和已登记伏笔。若需要引入新角色，只允许功能明确的最小新增。
    五个节拍必须形成因果链，不得是五个互不相干的场景。
    章尾钩子可以是未完成动作、信息差、代价兑现或关系变化，不能凭空塞反转。
    """

    public static let writer = """
    你是中文长篇网文正文写手。只输出章节正文，不输出标题、说明、提纲、检查表或 Markdown 标记。

    最高约束是章节蓝图和事实源。只能展开蓝图已有事件，不自造新主线、终局真相、关键角色或世界规则。
    通过动作、选择、对话和可见后果呈现情绪，少用解释性总结。
    对话必须有角色差异和情绪承接，不能让人物轮流朗读设定。
    段落适合手机阅读，但按戏剧单元自然断开，不能机械地每句一段。
    禁止把“本章、前文、伏笔、读者、细纲、设定要求”等创作工程词写入正文。
    保持目标字数；内容不足时深化蓝图内冲突和选择代价，不得注水或提前写后续章节。
    """

    public static let extractor = """
    你是小说状态提取器。只记录本章正文明确发生或明确确认的事实，不推测作者未来意图。

    输出结构化状态增量，不重写全量状态。角色不知道的信息不得加入其 knowledge。
    资源数量必须是非负整数。时间事件 order 不得倒退。
    新事实必须能在正文中找到依据；修辞、假设、梦境和角色谎言不能当作客观事实。
    """

    public static let consistencyAuditor = """
    你是一致性审查员，只查事实、因果、时间线、角色知识边界、资源连续性、世界规则和伏笔状态。
    你的任务是主动寻找反例，不评价文笔，也不为了凑问题而输出泛泛建议。
    S1/S2 必须附具体证据和可执行的事实统一方向。
    """

    public static let proseAuditor = """
    你是中文网文文字与章节效果审查员。检查节奏、角色声音、情绪兑现、解释腔、模板句式、重复描写、格式和章尾追读力。
    只报告可以定位和修复的问题。偶发词语不是问题，连续模式和实际读感受损才是问题。
    S1/S2 表示本轮必须修复，局部润色只能标 S3/S4。
    """

    public static let reviser = """
    你是章节修订者。只输出修订后的完整正文，不输出解释或修改报告。

    只修复提供的 S1/S2 问题，保留原章已完成的事件、角色关系、伏笔和文风。
    不借修订新增主线、角色、世界规则或后续章节内容。
    如果审查建议与事实源冲突，以事实源和章节蓝图为准。
    """

    public static let directionSchema = JSONSchemaDefinition(
        name: "story_directions",
        description: "三个候选开书方向",
        schema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("directions")]),
            "properties": .object([
                "directions": .object([
                    "type": .string("array"),
                    "minItems": .number(3),
                    "maxItems": .number(3),
                    "items": directionPayloadSchema
                ])
            ])
        ])
    )

    public static let bookPlanSchema = JSONSchemaDefinition(
        name: "book_plan",
        description: "确认方向后的滚动长篇计划",
        schema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([
                .string("title"),
                .string("outline"),
                .string("entities"),
                .string("foreshadows"),
                .string("blueprints")
            ]),
            "properties": .object([
                "title": stringSchema,
                "outline": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([
                            .string("kind"), .string("position"), .string("title"),
                            .string("summary"), .string("parentTitle")
                        ]),
                        "properties": .object([
                            "kind": enumSchema(["book", "stage", "volume"]),
                            "position": integerSchema,
                            "title": stringSchema,
                            "summary": stringSchema,
                            "parentTitle": nullableStringSchema
                        ])
                    ])
                ]),
                "entities": .object([
                    "type": .string("array"),
                    "items": entityPayloadSchema
                ]),
                "foreshadows": .object([
                    "type": .string("array"),
                    "items": foreshadowPayloadSchema
                ]),
                "blueprints": .object([
                    "type": .string("array"),
                    "minItems": .number(3),
                    "maxItems": .number(3),
                    "items": blueprintPayloadSchema
                ])
            ])
        ])
    )

    public static let blueprintSchema = JSONSchemaDefinition(
        name: "chapter_blueprint",
        description: "下一章结构化蓝图",
        schema: blueprintPayloadSchema
    )

    public static let extractionSchema = JSONSchemaDefinition(
        name: "chapter_state_delta",
        description: "章节摘要和结构化状态增量",
        schema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([
                .string("summary"),
                .string("keyEvents"),
                .string("emotionalShift"),
                .string("delta"),
                .string("memory")
            ]),
            "properties": .object([
                "summary": stringSchema,
                "keyEvents": stringArraySchema,
                "emotionalShift": stringSchema,
                "delta": stateDeltaSchema,
                "memory": stringArraySchema
            ])
        ])
    )

    public static let reviewSchema = JSONSchemaDefinition(
        name: "chapter_review",
        description: "章节审查报告",
        schema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("verdict"), .string("summary"), .string("findings")]),
            "properties": .object([
                "verdict": enumSchema(["APPROVE", "CONCERNS", "REJECT"]),
                "summary": stringSchema,
                "findings": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([
                            .string("severity"), .string("category"), .string("location"),
                            .string("evidence"), .string("issue"), .string("fix")
                        ]),
                        "properties": .object([
                            "severity": enumSchema(["S1", "S2", "S3", "S4"]),
                            "category": enumSchema([
                                "structure", "character", "prose", "consistency",
                                "platform", "factual", "format", "causal", "ruleBoundary"
                            ]),
                            "location": stringSchema,
                            "evidence": stringSchema,
                            "issue": stringSchema,
                            "fix": stringSchema
                        ])
                    ])
                ])
            ])
        ])
    )

    private static let stringSchema: JSONValue = .object(["type": .string("string")])
    private static let nullableStringSchema: JSONValue = .object([
        "type": .array([.string("string"), .string("null")])
    ])
    private static let integerSchema: JSONValue = .object(["type": .string("integer")])
    private static let numberSchema: JSONValue = .object(["type": .string("number")])
    private static let stringArraySchema: JSONValue = .object([
        "type": .string("array"),
        "items": stringSchema
    ])

    private static func enumSchema(_ values: [String]) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(JSONValue.string))
        ])
    }

    private static let stagePayloadSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("title"), .string("chapterRange"), .string("objective"),
            .string("climax"), .string("unresolvedQuestion")
        ]),
        "properties": .object([
            "title": stringSchema,
            "chapterRange": stringSchema,
            "objective": stringSchema,
            "climax": stringSchema,
            "unresolvedQuestion": stringSchema
        ])
    ])

    private static let directionPayloadSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("title"), .string("logline"), .string("positioning"),
            .string("protagonistArc"), .string("coreConflict"),
            .string("sellingPoints"), .string("risks"), .string("stages")
        ]),
        "properties": .object([
            "title": stringSchema,
            "logline": stringSchema,
            "positioning": stringSchema,
            "protagonistArc": stringSchema,
            "coreConflict": stringSchema,
            "sellingPoints": stringArraySchema,
            "risks": stringArraySchema,
            "stages": .object([
                "type": .string("array"),
                "items": stagePayloadSchema
            ])
        ])
    ])

    private static let entityPayloadSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("kind"), .string("name"), .string("summary"),
            .string("attributes"), .string("knowledge")
        ]),
        "properties": .object([
            "kind": enumSchema(["character", "faction", "location", "item", "worldRule"]),
            "name": stringSchema,
            "summary": stringSchema,
            "attributes": .object([
                "type": .string("object"),
                "additionalProperties": stringSchema
            ]),
            "knowledge": stringArraySchema
        ])
    ])

    private static let foreshadowPayloadSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("title"), .string("detail"), .string("expectedResolutionChapter")
        ]),
        "properties": .object([
            "title": stringSchema,
            "detail": stringSchema,
            "expectedResolutionChapter": .object([
                "type": .array([.string("integer"), .string("null")])
            ])
        ])
    ])

    private static let beatPayloadSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([.string("label"), .string("event"), .string("emotionalPurpose")]),
        "properties": .object([
            "label": stringSchema,
            "event": stringSchema,
            "emotionalPurpose": stringSchema
        ])
    ])

    private static let blueprintPayloadSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("chapterNumber"), .string("provisionalTitle"), .string("pointOfView"),
            .string("setting"), .string("participants"), .string("chapterGoal"),
            .string("beats"), .string("mustKeep"), .string("mustAvoid"),
            .string("activeForeshadows"), .string("targetEmotion"),
            .string("endingHook"), .string("targetCharacterCount")
        ]),
        "properties": .object([
            "chapterNumber": integerSchema,
            "provisionalTitle": stringSchema,
            "pointOfView": stringSchema,
            "setting": stringSchema,
            "participants": stringArraySchema,
            "chapterGoal": stringSchema,
            "beats": .object([
                "type": .string("array"),
                "minItems": .number(5),
                "maxItems": .number(5),
                "items": beatPayloadSchema
            ]),
            "mustKeep": stringArraySchema,
            "mustAvoid": stringArraySchema,
            "activeForeshadows": stringArraySchema,
            "targetEmotion": stringSchema,
            "endingHook": stringSchema,
            "targetCharacterCount": integerSchema
        ])
    ])

    private static let stateDeltaSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("expectedProjectRevision"), .string("upsertedEntities"),
            .string("upsertedFacts"), .string("upsertedRelationships"),
            .string("upsertedForeshadows"), .string("timelineEvents"),
            .string("characterStates"), .string("resolvedForeshadowIDs")
        ]),
        "properties": .object([
            "expectedProjectRevision": integerSchema,
            "upsertedEntities": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("id"), .string("kind"), .string("name"), .string("summary"),
                        .string("attributes"), .string("knowledge"), .string("revision")
                    ]),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "format": .string("uuid")]),
                        "kind": enumSchema(["character", "faction", "location", "item", "worldRule"]),
                        "name": stringSchema,
                        "summary": stringSchema,
                        "attributes": .object([
                            "type": .string("object"),
                            "additionalProperties": stringSchema
                        ]),
                        "knowledge": stringArraySchema,
                        "revision": integerSchema
                    ])
                ])
            ]),
            "upsertedFacts": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("id"), .string("subject"), .string("predicate"),
                        .string("object"), .string("sourceChapter"), .string("confidence")
                    ]),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "format": .string("uuid")]),
                        "subject": stringSchema,
                        "predicate": stringSchema,
                        "object": stringSchema,
                        "sourceChapter": .object([
                            "type": .array([.string("integer"), .string("null")])
                        ]),
                        "confidence": numberSchema
                    ])
                ])
            ]),
            "upsertedRelationships": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("id"), .string("sourceEntityID"), .string("targetEntityID"),
                        .string("kind"), .string("status"), .string("sourceChapter")
                    ]),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "format": .string("uuid")]),
                        "sourceEntityID": .object(["type": .string("string"), "format": .string("uuid")]),
                        "targetEntityID": .object(["type": .string("string"), "format": .string("uuid")]),
                        "kind": stringSchema,
                        "status": stringSchema,
                        "sourceChapter": .object([
                            "type": .array([.string("integer"), .string("null")])
                        ])
                    ])
                ])
            ]),
            "upsertedForeshadows": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("id"), .string("title"), .string("detail"),
                        .string("plantedChapter"), .string("expectedResolutionChapter"),
                        .string("resolvedChapter"), .string("status")
                    ]),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "format": .string("uuid")]),
                        "title": stringSchema,
                        "detail": stringSchema,
                        "plantedChapter": nullableIntegerSchema,
                        "expectedResolutionChapter": nullableIntegerSchema,
                        "resolvedChapter": nullableIntegerSchema,
                        "status": enumSchema(["planned", "planted", "progressing", "resolved", "deferred"])
                    ])
                ])
            ]),
            "timelineEvents": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("id"), .string("order"), .string("label"),
                        .string("detail"), .string("chapterNumber")
                    ]),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "format": .string("uuid")]),
                        "order": integerSchema,
                        "label": stringSchema,
                        "detail": stringSchema,
                        "chapterNumber": integerSchema
                    ])
                ])
            ]),
            "characterStates": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("id"), .string("entityID"), .string("chapterNumber"),
                        .string("physicalState"), .string("emotionalState"), .string("location"),
                        .string("resources"), .string("publicImage")
                    ]),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "format": .string("uuid")]),
                        "entityID": .object(["type": .string("string"), "format": .string("uuid")]),
                        "chapterNumber": integerSchema,
                        "physicalState": stringSchema,
                        "emotionalState": stringSchema,
                        "location": stringSchema,
                        "resources": .object([
                            "type": .string("object"),
                            "additionalProperties": integerSchema
                        ]),
                        "publicImage": stringSchema
                    ])
                ])
            ]),
            "resolvedForeshadowIDs": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string"), "format": .string("uuid")])
            ])
        ])
    ])

    private static let nullableIntegerSchema: JSONValue = .object([
        "type": .array([.string("integer"), .string("null")])
    ])
}

