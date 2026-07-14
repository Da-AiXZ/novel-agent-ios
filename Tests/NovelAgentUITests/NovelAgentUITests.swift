import XCTest

final class NovelAgentUITests: XCTestCase {
    func testCreateProjectAndOpenInterview() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["createProject"].tap()
        let title = app.textFields["newProjectTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("测试长篇")
        app.buttons["confirmCreateProject"].tap()

        let row = app.staticTexts["测试长篇"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textViews["interviewAnswer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["primaryAction"].exists)
    }
}

