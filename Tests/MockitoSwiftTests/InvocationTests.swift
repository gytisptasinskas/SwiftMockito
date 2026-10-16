import XCTest
import MockitoSwift

final class InvocationTests: XCTestCase {
    func testInvocationPreservesMemberIdentityAndArgumentLabels() {
        let invocation = Invocation(
            mockID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            member: "fetch(id:)",
            argumentLabels: ["id"],
            sourceLocation: .init(fileID: "InvocationTests.swift", line: 17),
            phase: .dispatch
        )

        XCTAssertEqual(invocation.member, "fetch(id:)")
        XCTAssertEqual(invocation.argumentLabels, ["id"])
        XCTAssertEqual(invocation.mockID, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(invocation.phase, .dispatch)
    }

    func testInvocationPreservesSourceLocation() {
        let sourceLocation = Invocation.SourceLocation(fileID: "ClientTests.swift", line: 42)
        let invocation = Invocation(
            mockID: UUID(),
            member: "save(_:)",
            argumentLabels: ["_"],
            sourceLocation: sourceLocation,
            phase: .capture
        )

        XCTAssertEqual(invocation.sourceLocation.fileID, "ClientTests.swift")
        XCTAssertEqual(invocation.sourceLocation.line, 42)
    }

    func testMissingStubErrorDescribesInvocationAndSourceLocation() {
        let invocation = Invocation(
            mockID: UUID(),
            member: "fetch(id:)",
            argumentLabels: ["id"],
            sourceLocation: .init(fileID: "ClientTests.swift", line: 42),
            phase: .dispatch
        )

        XCTAssertEqual(
            MissingStubError(invocation: invocation).description,
            "Missing stub for fetch(id:) at ClientTests.swift:42."
        )
    }
}
