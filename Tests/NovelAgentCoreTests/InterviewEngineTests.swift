import XCTest
@testable import NovelAgentCore

final class InterviewEngineTests: XCTestCase {
    func testInterviewBuildsBriefAndClampsLength() {
        let projectID = UUID()
        var session = InterviewSession(projectID: projectID)
        let answers = [
            "玄幻升级",
            "起点",
            "主角能看见所有功法的代价",
            "谨慎但嘴硬的落魄少主",
            "重建家族，失败会失去妹妹",
            "垄断功法的宗门联盟",
            "任何能力都必须支付等价记忆",
            "燃",
            "99999",
            "不要无代价升级"
        ]
        let engine = InterviewEngine()
        for answer in answers {
            session = engine.answer(answer, session: session)
        }

        let brief = engine.buildBrief(from: session)
        XCTAssertEqual(brief.genre, "玄幻升级")
        XCTAssertEqual(brief.targetPlatform, .qidian)
        XCTAssertEqual(brief.targetChapterCount, 2_000)
        XCTAssertEqual(session.currentQuestionIndex, InterviewEngine.questions.count)
    }
}

