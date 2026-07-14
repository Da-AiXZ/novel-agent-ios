import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NovelAgentCore

public struct SSEMessage: Hashable, Sendable {
    public var event: String?
    public var id: String?
    public var data: String

    public init(event: String? = nil, id: String? = nil, data: String) {
        self.event = event
        self.id = id
        self.data = data
    }
}

public struct SSEParser: Sendable {
    private var event: String?
    private var id: String?
    private var dataLines: [String] = []

    public init() {}

    public mutating func consume(line: String) -> SSEMessage? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        switch field {
        case "event":
            event = value
        case "id":
            id = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    public mutating func finish() -> SSEMessage? {
        dispatch()
    }

    private mutating func dispatch() -> SSEMessage? {
        guard !dataLines.isEmpty else {
            event = nil
            return nil
        }
        let message = SSEMessage(event: event, id: id, data: dataLines.joined(separator: "\n"))
        event = nil
        dataLines.removeAll(keepingCapacity: true)
        return message
    }
}

public struct SSETransport: Sendable {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func stream(_ request: URLRequest) -> AsyncThrowingStream<SSEMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
#if canImport(Darwin)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ProviderError.invalidResponse("缺少 HTTP 响应")
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                        }
                        throw Self.httpError(response: http, body: body)
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if let message = parser.consume(line: line) {
                            continuation.yield(message)
                        }
                    }
                    if let message = parser.finish() {
                        continuation.yield(message)
                    }
#else
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ProviderError.invalidResponse("缺少 HTTP 响应")
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw Self.httpError(response: http, body: data)
                    }
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw CoreError.invalidUTF8
                    }
                    var parser = SSEParser()
                    for line in text.components(separatedBy: .newlines) {
                        if let message = parser.consume(line: line) {
                            continuation.yield(message)
                        }
                    }
                    if let message = parser.finish() {
                        continuation.yield(message)
                    }
#endif
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("缺少 HTTP 响应")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw Self.httpError(response: http, body: data)
        }
        return data
    }

    private static func httpError(response: HTTPURLResponse, body: Data) -> ProviderError {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        let raw = String(data: body, encoding: .utf8) ?? "请求失败"
        let message = extractErrorMessage(raw) ?? raw.prefix(600).description
        return .http(
            statusCode: response.statusCode,
            message: message,
            retryAfterSeconds: retryAfter
        )
    }

    private static func extractErrorMessage(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONDecoder.novelAgent.decode(JSONValue.self, from: data),
              let object = json.objectValue
        else {
            return nil
        }
        if let error = object["error"]?.objectValue,
           let message = error["message"]?.stringValue {
            return message
        }
        return object["message"]?.stringValue
    }
}

