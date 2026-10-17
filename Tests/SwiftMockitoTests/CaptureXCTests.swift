import XCTest
@testable import SwiftMockito

final class CaptureXCTests: XCTestCase {
    let mock = SampleMock()

    func testClosureCapturingSelfIsAccepted() async throws {
        when { try await self.mock.fetch(id: "1") }.thenReturn("xc")
        let value = try await mock.fetch(id: "1")
        XCTAssertEqual(value, "xc")
        verify { try await self.mock.fetch(id: "1") }.called(1)
    }
}
