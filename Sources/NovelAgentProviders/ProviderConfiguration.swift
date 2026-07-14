import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NovelAgentCore

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case openAIResponses
    case anthropicMessages
    case openAICompatible

    public var displayName: String {
        switch self {
        case .openAIResponses:
            "OpenAI"
        case .anthropicMessages:
            "Anthropic"
        case .openAICompatible:
            "兼容接口"
        }
    }
}

public struct ProviderConfiguration: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ProviderKind
    public var baseURL: URL
    public var strongModel: String
    public var fastModel: String
    public var embeddingModel: String?
    public var qualityPreset: QualityPreset

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ProviderKind,
        baseURL: URL,
        strongModel: String,
        fastModel: String,
        embeddingModel: String? = nil,
        qualityPreset: QualityPreset = .quality
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.strongModel = strongModel
        self.fastModel = fastModel
        self.embeddingModel = embeddingModel
        self.qualityPreset = qualityPreset
    }

    public var routing: ModelRouting {
        ModelRouting(
            preset: qualityPreset,
            strongModel: strongModel,
            fastModel: fastModel,
            embeddingModel: embeddingModel
        )
    }

    public static func defaultBaseURL(for kind: ProviderKind) -> URL {
        switch kind {
        case .openAIResponses:
            URL(string: "https://api.openai.com/v1")!
        case .anthropicMessages:
            URL(string: "https://api.anthropic.com/v1")!
        case .openAICompatible:
            URL(string: "https://api.deepseek.com/v1")!
        }
    }
}

public enum ProviderFactory {
    public static func make(
        configuration: ProviderConfiguration,
        apiKey: String,
        session: URLSession = .novelAgent
    ) throws -> any LLMProvider {
        try validateHTTPS(configuration.baseURL)
        switch configuration.kind {
        case .openAIResponses:
            return OpenAIResponsesProvider(
                baseURL: configuration.baseURL,
                apiKey: apiKey,
                session: session
            )
        case .anthropicMessages:
            return AnthropicMessagesProvider(
                baseURL: configuration.baseURL,
                apiKey: apiKey,
                session: session
            )
        case .openAICompatible:
            return OpenAICompatibleProvider(
                baseURL: configuration.baseURL,
                apiKey: apiKey,
                session: session
            )
        }
    }

    private static func validateHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw ProviderError.invalidConfiguration("自定义接口必须是有效的 HTTPS 地址")
        }
    }
}

public extension URLSession {
    static var novelAgent: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
#if canImport(Darwin)
        configuration.waitsForConnectivity = true
#endif
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }
}
