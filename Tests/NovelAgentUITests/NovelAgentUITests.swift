import XCTest

@MainActor
final class NovelAgentUITests: XCTestCase {
    func testCreateProjectAndOpenInterview() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["createProject"].tap()
        let title = app.textFields["newProjectTitle"]
        let titleExists = title.waitForExistence(timeout: 5)
        XCTAssertTrue(titleExists)
        title.tap()
        title.typeText("测试长篇")
        app.buttons["confirmCreateProject"].tap()

        let row = app.staticTexts["测试长篇"]
        let rowExists = row.waitForExistence(timeout: 5)
        XCTAssertTrue(rowExists)
        row.tap()
        let answerExists = app.textViews["interviewAnswer"].waitForExistence(timeout: 5)
        let primaryExists = app.buttons["primaryAction"].exists
        XCTAssertTrue(answerExists)
        XCTAssertTrue(primaryExists)
    }
}
