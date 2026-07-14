import XCTest
@testable import NovelAgentProviders

final class SSEParserTests: XCTestCase {
    func testParsesMultilineEventAndIgnoresComments() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(line: ": keepalive"))
        XCTAssertNil(parser.consume(line: "event: message"))
        XCTAssertNil(parser.consume(line: "id: 42"))
        XCTAssertNil(parser.consume(line: "data: first"))
        XCTAssertNil(parser.consume(line: "data: second"))
        let message = parser.consume(line: "")

        XCTAssertEqual(message?.event, "message")
        XCTAssertEqual(message?.id, "42")
        XCTAssertEqual(message?.data, "first\nsecond")
    }
}

