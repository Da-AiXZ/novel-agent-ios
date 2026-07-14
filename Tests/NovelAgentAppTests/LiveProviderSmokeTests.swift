import XCTest
import NovelAgentCore
import NovelAgentProviders

final class LiveProviderSmokeTests: XCTestCase {
    func testConfiguredProviderWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NOVELAGENT_RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live provider tests are disabled")
        }
        guard let kindRaw = environment["NOVELAGENT_PROVIDER_KIND"],
              let kind = ProviderKind(rawValue: kindRaw),
              let baseRaw = environment["NOVELAGENT_BASE_URL"],
              let baseURL = URL(string: baseRaw),
              let model = environment["NOVELAGENT_MODEL"],
              let apiKey = environment["NOVELAGENT_API_KEY"],
              !apiKey.isEmpty
        else {
            XCTFail("Live provider environment is incomplete")
            return
        }

        let configuration = ProviderConfiguration(
            name: "CI smoke",
            kind: kind,
            baseURL: baseURL,
            strongModel: model,
            fastModel: model
        )
        let provider = try ProviderFactory.make(
            configuration: configuration,
            apiKey: apiKey
        )
        let result = try await provider.probe(model: model)
        XCTAssertGreaterThanOrEqual(result.latencyMilliseconds, 0)
    }
}

