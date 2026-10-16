import Foundation
import XCTest
import SwiftMockito

final class StubbingTests: XCTestCase {
    private enum SampleError: Error, Equatable {
        case unavailable
    }

    private struct NonEquatableValue {}

    func testExactArgumentsCompareEquatableValuesAndDiagnoseUnsupportedValues() throws {
        let call = invocation(member: "fetch(id:)", labels: ["id", "limit"])

        let first = try ExactArguments(["42", 3], for: call)
        let equal = try ExactArguments(["42", 3], for: call)
        let different = try ExactArguments(["43", 3], for: call)

        XCTAssertEqual(first, equal)
        XCTAssertNotEqual(first, different)

        XCTAssertThrowsError(try ExactArguments([NonEquatableValue()], for: call)) { error in
            let unsupported = error as? UnsupportedExactMatchingError
            XCTAssertEqual(unsupported?.member, "fetch(id:)")
            XCTAssertEqual(unsupported?.position, 0)
        }
    }

    func testNewestMatchingStubWinsAndReturnsItsValue() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "fetch(id:)", labels: ["id"])
        let arguments = try ExactArguments(["42"], for: call)

        runtime.stub(for: call, arguments: arguments).thenReturn("older")
        runtime.stub(for: call, arguments: arguments).thenReturn("newer")

        let result: String = try runtime.resolve(call, arguments: arguments)
        XCTAssertEqual(result, "newer")
        XCTAssertEqual(runtime.recordedInvocations, [call])
    }

    func testStubDoesNotMatchDifferentArgumentValues() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "fetch(id:)", labels: ["id"])
        let configuredArguments = try ExactArguments(["42"], for: call)
        let actualArguments = try ExactArguments(["43"], for: call)
        runtime.stub(for: call, arguments: configuredArguments).thenReturn("answer")

        XCTAssertThrowsError(try runtime.resolve(call, arguments: actualArguments) as String) { error in
            XCTAssertEqual((error as? MissingStubError)?.invocation, call)
        }
    }

    func testThenThrowPropagatesTheConfiguredError() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "save(_:)", labels: ["_"])
        let arguments = try ExactArguments(["draft"], for: call)
        runtime.stub(for: call, arguments: arguments).thenThrow(SampleError.unavailable)

        XCTAssertThrowsError(try runtime.resolve(call, arguments: arguments) as String) { error in
            XCTAssertEqual(error as? SampleError, .unavailable)
        }
    }

    func testThenAnswerReceivesActualArgumentsAndReturnsItsTypedResult() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "format(_:)", labels: ["_"])
        let configuredArguments = try ExactArguments(["hello"], for: call)
        let actualArguments = try ExactArguments(["hello"], for: call)

        runtime.stub(for: call, arguments: configuredArguments).thenAnswer { values in
            let value = values[0] as! String
            return "<\(value)>"
        }

        let result: String = try runtime.resolve(call, arguments: actualArguments)
        XCTAssertEqual(result, "<hello>")
    }

    func testUnmatchedNonVoidInvocationThrowsMissingStubError() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "fetch(id:)", labels: ["id"])
        let arguments = try ExactArguments(["missing"], for: call)

        XCTAssertThrowsError(try runtime.resolve(call, arguments: arguments) as String) { error in
            XCTAssertEqual((error as? MissingStubError)?.invocation, call)
        }
        XCTAssertEqual(runtime.recordedInvocations, [call])
    }

    func testUnmatchedVoidInvocationRecordsAndSucceeds() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "clear()", labels: [])
        let arguments = try ExactArguments([], for: call)

        let result: Void = try runtime.resolve(call, arguments: arguments)

        XCTAssertEqual(runtime.recordedInvocations, [call])
        XCTAssertNotNil(result as Any?)
    }

    func testInvocationRecordingIsSafeAcrossConcurrentCalls() throws {
        let runtime = MockRuntime()
        let call = invocation(member: "tick()", labels: [])
        let arguments = try ExactArguments([], for: call)
        let count = 500

        DispatchQueue.concurrentPerform(iterations: count) { _ in
            runtime.record(call, arguments: arguments)
        }

        XCTAssertEqual(runtime.recordedInvocations.count, count)
    }

    private func invocation(member: String, labels: [String]) -> Invocation {
        Invocation(
            mockID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            member: member,
            argumentLabels: labels,
            sourceLocation: .init(fileID: "StubbingTests.swift", line: 1),
            phase: .dispatch
        )
    }
}
