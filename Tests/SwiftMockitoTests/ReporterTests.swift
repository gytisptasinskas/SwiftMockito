import Testing
@testable import SwiftMockito

@Suite struct ReporterTests {
    @Test func callSiteDescriptionIsFileLineColumn() {
        let site = CallSite(fileID: "App/Tests.swift", filePath: "/x/Tests.swift", line: 12, column: 9)
        #expect(site.description == "App/Tests.swift:12:9")
    }

    @Test func routesToSwiftTestingIssueWithLocation() {
        let site = CallSite()
        withKnownIssue {
            Reporter.fail("boom", at: site)
        } matching: { issue in
            issue.comments.contains { $0.rawValue == "boom" }
                && issue.sourceLocation?.line == Int(site.line)
                && issue.sourceLocation?.fileID == site.fileID
        }
    }

    @Test func sinkInterceptsFailures() {
        let box = MessageBox()
        Reporter.$sink.withValue({ message, _ in box.append(message) }) {
            Reporter.fail("captured", at: CallSite())
        }
        #expect(box.messages == ["captured"])
    }
}
