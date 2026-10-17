import XCTest
@testable import SwiftMockito

final class ReporterXCTests: XCTestCase {
    func testRoutesToXCTFailOutsideSwiftTesting() {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("xctest boom") }
        XCTExpectFailure("Reporter must call XCTFail", options: options) {
            Reporter.fail("xctest boom", at: CallSite())
        }
    }
}
