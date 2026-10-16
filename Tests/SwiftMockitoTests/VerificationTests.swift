// Replaced in Task 8.
#if false
import Foundation
import XCTest
@testable import SwiftMockito

/// A hand-written stand-in for a generated mock. Task 4/5 will generate this shape from a
/// `@GenerateMock` protocol; for Task 3 we drive the same capture/dispatch contract by
/// hand: while `CaptureContext.current` is set, record invocation shape and return a
/// placeholder without touching the runtime; otherwise dispatch for real.
private final class SampleMock: Mock {
    func fetch(id: String) throws -> String {
        try dispatchOrCapture(member: "fetch(id:)", labels: ["id"], values: [id], placeholder: "")
    }

    func save(_ value: String) throws {
        try dispatchOrCapture(member: "save(_:)", labels: ["_"], values: [value], placeholder: ())
    }

    func fetchAsync(id: String) async throws -> String {
        try dispatchOrCapture(member: "fetchAsync(id:)", labels: ["id"], values: [id], placeholder: "")
    }

    private func dispatchOrCapture<Value>(
        member: String,
        labels: [String],
        values: [Any],
        placeholder: Value
    ) throws -> Value {
        let invocation = Invocation(
            mockID: id,
            member: member,
            argumentLabels: labels,
            sourceLocation: .init(fileID: "SampleMock.swift", line: 1),
            phase: CaptureContext.current == nil ? .dispatch : .capture
        )
        if let session = CaptureContext.current {
            let arguments = try? ExactArguments(values, for: invocation)
            session.record(invocation, arguments: arguments, runtime: runtime)
            return placeholder
        }
        let arguments = try ExactArguments(values, for: invocation)
        return try runtime.resolve(invocation, arguments: arguments)
    }
}

private struct SampleError: Error, Equatable {}

/// Thread-safe collector used to capture `FailureReporting` messages during a test instead
/// of letting them fail the enclosing XCTest via the real `XCTFail`/`Issue.record` path.
/// `FailureReporting.override` is a `@Sendable` closure, so a plain captured `var` cannot
/// back it directly under Swift 6 strict concurrency.
private final class MessageSink: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return messages.count
    }

    var isEmpty: Bool { count == 0 }
}

final class VerificationTests: XCTestCase {
    // MARK: - capture does not dispatch

    func testWhenCapturesShapeWithoutDispatchingOrThrowingConfiguredErrors() throws {
        let mock = SampleMock()
        // If capture dispatched for real, this would throw MissingStubError (no stub yet).
        try when(mock.fetch(id: "42")).thenThrow(SampleError())

        // Capture must not have recorded a dispatch-phase interaction.
        XCTAssertEqual(mock.runtime.recordedInvocations, [])

        // The stub now resolves for real dispatch.
        XCTAssertThrowsError(try mock.fetch(id: "42")) { error in
            XCTAssertEqual(error as? SampleError, SampleError())
        }
    }

    func testVerifyDoesNotCountCapturePhaseCalls() throws {
        let mock = SampleMock()
        try mock.save("draft")

        // Merely building the verify expression must not add another interaction.
        try verify(mock.save("draft")).called(1)
        XCTAssertEqual(mock.runtime.recordedInvocations.count, 1)
    }

    // MARK: - async throws closure capture

    func testAsyncThrowsClosureFormCapturesWithoutRealDispatch() async throws {
        let mock = SampleMock()
        try await when { try await mock.fetchAsync(id: "7") }.thenReturn("seven")

        let result = try await mock.fetchAsync(id: "7")
        XCTAssertEqual(result, "seven")

        try await verify { try await mock.fetchAsync(id: "7") }.called(once())
    }

    // MARK: - counts

    func testCalledWithExactCountConsumesAllMatchingCalls() throws {
        let mock = SampleMock()
        try mock.save("a")
        try mock.save("a")

        try verify(mock.save("a")).called(2)
        XCTAssertTrue(mock.runtime.interactionSnapshot(for: mock.id).allSatisfy(\.verified))
    }

    func testCalledAtLeastAcceptsAMatchingLowerBound() throws {
        let mock = SampleMock()
        try mock.save("b")
        try mock.save("b")
        try mock.save("b")

        XCTAssertTrue(try verify(mock.save("b")).called(atLeast: 2))
    }

    func testCalledAtMostAcceptsAMatchingUpperBound() throws {
        let mock = SampleMock()
        try mock.save("d")

        XCTAssertTrue(try verify(mock.save("d")).called(atMost: 3))
    }

    func testOnceHelperMatchesExactlyOneCall() throws {
        let mock = SampleMock()
        try mock.save("once-only")

        XCTAssertTrue(try verify(mock.save("once-only")).called(once()))
    }

    func testCalledFailsAndReportsWhenCountDoesNotMatch() throws {
        let mock = SampleMock()
        try mock.save("c")

        let sink = MessageSink()
        let passed = try FailureReporting.$override.withValue({ sink.record($0) }) {
            try verify(mock.save("c")).called(2)
        }
        XCTAssertFalse(passed)
        XCTAssertEqual(sink.count, 1)
    }

    // MARK: - never

    func testVerifyNeverPassesWhenArgumentsDoNotMatch() throws {
        let mock = SampleMock()
        try mock.save("actual")

        XCTAssertTrue(try verifyNever(mock.save("different")))
    }

    func testVerifyNeverFailsAndReportsWhenTheCallDidHappen() throws {
        let mock = SampleMock()
        try mock.save("happened")

        let sink = MessageSink()
        let passed = try FailureReporting.$override.withValue({ sink.record($0) }) {
            try verifyNever(mock.save("happened"))
        }
        XCTAssertFalse(passed)
        XCTAssertEqual(sink.count, 1)
    }

    // MARK: - consumption

    func testVerifiedCallCannotBeVerifiedAgain() throws {
        let mock = SampleMock()
        try mock.save("single")

        XCTAssertTrue(try verify(mock.save("single")).called(1))

        let sink = MessageSink()
        let secondPassed = try FailureReporting.$override.withValue({ sink.record($0) }) {
            try verify(mock.save("single")).called(1)
        }
        XCTAssertFalse(secondPassed)
        XCTAssertEqual(sink.count, 1)
    }

    // MARK: - flexible order

    func testVerifyInOrderIgnoresUnrelatedCallsBetweenExpectedCalls() throws {
        let mock = SampleMock()
        try mock.save("first")
        try mock.save("unrelated")
        try mock.save("second")

        let sink = MessageSink()
        FailureReporting.$override.withValue({ sink.record($0) }) {
            verifyInOrder {
                try mock.save("first")
                try mock.save("second")
            }
        }

        XCTAssertTrue(sink.isEmpty)
    }

    func testVerifyInOrderFailsWhenRelativeOrderIsViolated() throws {
        let mock = SampleMock()
        try mock.save("second")
        try mock.save("first")

        let sink = MessageSink()
        FailureReporting.$override.withValue({ sink.record($0) }) {
            verifyInOrder {
                try mock.save("first")
                try mock.save("second")
            }
        }
        XCTAssertFalse(sink.isEmpty)
    }

    func testVerifyInOrderAsyncOverloadCapturesAwaitedCalls() async throws {
        let mock = SampleMock()
        try await when { try await mock.fetchAsync(id: "1") }.thenReturn("one")
        try await when { try await mock.fetchAsync(id: "2") }.thenReturn("two")

        _ = try await mock.fetchAsync(id: "1")
        try mock.save("between")
        _ = try await mock.fetchAsync(id: "2")

        await verifyInOrder {
            try await mock.fetchAsync(id: "1")
            try await mock.fetchAsync(id: "2")
        }

        try verify(mock.save("between")).called(1)
        XCTAssertTrue(verifyNoMoreInteractions(mock))
    }

    // MARK: - no more interactions

    func testVerifyNoMoreInteractionsPassesWhenEverythingIsVerified() throws {
        let mock = SampleMock()
        try mock.save("only")

        try verify(mock.save("only")).called(1)

        XCTAssertTrue(verifyNoMoreInteractions(mock))
    }

    func testVerifyNoMoreInteractionsFailsWhenACallIsUnverified() throws {
        let mock = SampleMock()
        try mock.save("verified")
        try mock.save("left-over")

        try verify(mock.save("verified")).called(1)

        let sink = MessageSink()
        let passed = FailureReporting.$override.withValue({ sink.record($0) }) {
            verifyNoMoreInteractions(mock)
        }
        XCTAssertFalse(passed)
        XCTAssertEqual(sink.count, 1)
    }

    // MARK: - reset

    func testResetClearsStubsAndRecordedInteractions() throws {
        let mock = SampleMock()
        try when(mock.fetch(id: "x")).thenReturn("configured")
        _ = try mock.fetch(id: "x")
        XCTAssertEqual(mock.runtime.recordedInvocations.count, 1)

        reset(mock)

        XCTAssertEqual(mock.runtime.recordedInvocations, [])
        XCTAssertThrowsError(try mock.fetch(id: "x")) { error in
            XCTAssertTrue(error is MissingStubError)
        }
    }

    // MARK: - misuse

    func testWhenReportsMisuseWhenZeroCallsAreCaptured() {
        let sink = MessageSink()
        let stub = FailureReporting.$override.withValue({ sink.record($0) }) {
            when(1 + 1).thenReturn(2)
        }
        XCTAssertEqual(sink.count, 1)
        // The returned stub is a harmless no-op; configuring it must not crash.
        stub.thenReturn(99)
    }

    func testVerifyReportsMisuseWhenMultipleCallsAreCaptured() async throws {
        let mock = SampleMock()
        try mock.save("a")
        try mock.save("b")

        let sink = MessageSink()
        let verification = try await FailureReporting.$override.withValue({ sink.record($0) }) {
            try await verify {
                try mock.save("a")
                try mock.save("b")
            }
        }
        XCTAssertEqual(sink.count, 1)
        XCTAssertFalse(verification.called(1))
    }
}

#endif
