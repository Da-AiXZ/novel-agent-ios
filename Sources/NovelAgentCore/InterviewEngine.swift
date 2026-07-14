import Foundation

public struct InterviewQuestion: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var prompt: String
    public var options: [String]
    public var placeholder: String

    public init(
        id: String,
        title: String,
        prompt: String,
        options: [String],
        placeholder: String
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.options = options
        self.placeholder = placeholder
    }
}

public struct InterviewSession: Codable, Hashable, Sendable {
    public var projectID: UUID
    public var currentQuestionIndex: Int
    public var answers: [String: String]

    public init(projectID: UUID, currentQuestionIndex: Int = 0, answers: [String: String] = [:]) {
        self.projectID = projectID
        self.currentQuestionIndex = currentQuestionIndex
        self.answers = answers
    }
}

public struct InterviewEngine: Sendable {
    public static let questions: [InterviewQuestion] = [
        InterviewQuestion(
            id: "genre",
            title: "题材",
            prompt: "你最想写哪类长篇网文？",
            options: ["都市脑洞", "玄幻升级", "悬疑推理", "古言权谋", "现言情感", "无限流"],
            placeholder: "也可以直接描述混合题材"
        ),
        InterviewQuestion(
            id: "platform",
            title: "平台",
            prompt: "你希望更贴近哪种阅读节奏？",
            options: ["通用网文", "番茄", "起点"],
            placeholder: "选择一个主要平台"
        ),
        InterviewQuestion(
            id: "coreHook",
            title: "核心梗",
            prompt: "用一句话说出这本书最吸引你的设定。",
            options: [],
            placeholder: "例如：全世界都能看见主角每天死亡倒计时"
        ),
        InterviewQuestion(
            id: "protagonist",
            title: "主角",
            prompt: "主角是谁？他最明显的缺陷或反差是什么？",
            options: [],
            placeholder: "身份、性格、缺陷或反差"
        ),
        InterviewQuestion(
            id: "desire",
            title: "欲望",
            prompt: "主角最想得到什么？失败会失去什么？",
            options: [],
            placeholder: "目标和失败代价"
        ),
        InterviewQuestion(
            id: "conflict",
            title: "矛盾",
            prompt: "阻止主角的核心力量是什么？",
            options: [],
            placeholder: "敌人、制度、秘密或自身弱点"
        ),
        InterviewQuestion(
            id: "worldRules",
            title: "世界规则",
            prompt: "这个世界最不能被破坏的一条规则是什么？",
            options: [],
            placeholder: "能力边界、代价或社会规则"
        ),
        InterviewQuestion(
            id: "emotion",
            title: "读者感受",
            prompt: "你希望读者追读时最常获得什么感受？",
            options: ["爽感", "紧张", "甜", "燃", "治愈", "恐惧", "心疼"],
            placeholder: "选择主情绪，也可以自己描述"
        ),
        InterviewQuestion(
            id: "length",
            title: "篇幅",
            prompt: "第一阶段准备写多少章？",
            options: ["50", "100", "200"],
            placeholder: "输入章数"
        ),
        InterviewQuestion(
            id: "exclusions",
            title: "创作禁区",
            prompt: "有哪些内容、套路或表达你明确不想出现？",
            options: ["没有特别禁区"],
            placeholder: "可写题材雷点、剧情禁区或文风要求"
        )
    ]

    public init() {}

    public func currentQuestion(for session: InterviewSession) -> InterviewQuestion? {
        guard Self.questions.indices.contains(session.currentQuestionIndex) else { return nil }
        return Self.questions[session.currentQuestionIndex]
    }

    public func answer(
        _ answer: String,
        session: InterviewSession
    ) -> InterviewSession {
        guard let question = currentQuestion(for: session) else { return session }
        var copy = session
        copy.answers[question.id] = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.currentQuestionIndex += 1
        return copy
    }

    public func moveBack(session: InterviewSession) -> InterviewSession {
        var copy = session
        copy.currentQuestionIndex = max(0, session.currentQuestionIndex - 1)
        return copy
    }

    public func buildBrief(from session: InterviewSession) -> StoryBrief {
        let platform = TargetPlatform(rawValue: session.answers["platform"] ?? "") ?? .general
        let chapterCount = Int(session.answers["length"] ?? "") ?? 100
        return StoryBrief(
            genre: session.answers["genre"] ?? "",
            targetPlatform: platform,
            coreHook: session.answers["coreHook"] ?? "",
            protagonist: session.answers["protagonist"] ?? "",
            protagonistDesire: session.answers["desire"] ?? "",
            coreConflict: session.answers["conflict"] ?? "",
            worldRules: session.answers["worldRules"] ?? "",
            targetEmotion: session.answers["emotion"] ?? "",
            targetChapterCount: max(20, min(chapterCount, 2_000)),
            exclusions: session.answers["exclusions"] ?? "",
            rawAnswers: session.answers
        )
    }
}
