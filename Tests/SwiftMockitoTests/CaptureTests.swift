import Foundation
import Testing
@testable import SwiftMockito

@Suite struct CaptureTests {
    let mock = SampleMock()

    func failures(_ body: () -> Void) -> [String] {
        let box = MessageBox()
        Reporter.$sink.withValue({ message, site in box.append("\(message) @\(site.fileID)") }, operation: body)
        return box.messages
    }

    @Test func captureNeverDispatches() {
        when { try await mock.fetch(id: "42") }.thenThrow(SampleError())
        when(mock.cached(id: "42")).thenReturn("x")
        #expect(mock.runtime.callsSnapshot().isEmpty)
    }

    @Test func asyncThrowingMemberIsCapturedWithoutAwaitAtCallSite() async throws {
        when { try await mock.fetch(id: "42") }.thenReturn("user")
        #expect(try await mock.fetch(id: "42") == "user")
    }

    @Test func setterIsCapturedFromClosure() {
        mock.token = "abc"
        verify { mock.token = "abc" }.called(1)
    }

    @Test func zeroCallsIsMisuseWithCallerLocation() {
        #expect(failures { when { 42 }.thenReturn(1) } == [
            "when: expected exactly one mock call, recorded 0. @SwiftMockitoTests/CaptureTests.swift"
        ])
    }

    @Test func twoCallsIsMisuse() {
        #expect(failures {
            when { _ = mock.cached(id: "1"); return mock.cached(id: "2") }.thenReturn("x" as String?)
        } == ["when: expected exactly one mock call, recorded 2 (SampleMock.cached(id:), SampleMock.cached(id:)). @SwiftMockitoTests/CaptureTests.swift"])
    }

    @Test func stubWhoseClosureTypeDiffersFromTheMemberIsRejected() {
        #expect(failures {
            when { try? await mock.fetch(id: "1") }.thenReturn(nil)
        } == ["when: the closure evaluates to Optional<String> but SampleMock.fetch(id:) returns String; put only the member call in the closure (no try?, ??, or conversions). @SwiftMockitoTests/CaptureTests.swift"])
        #expect(mock.runtime.stubsSnapshot(member: "fetch(id:)").isEmpty)
    }

    @Test func syncStubWhoseClosureTypeDiffersFromTheMemberIsRejected() {
        #expect(failures {
            when(mock.cached(id: "1") ?? "x").thenReturn("y")
        } == ["when: the closure evaluates to String but SampleMock.cached(id:) returns Optional<String>; put only the member call in the closure (no try?, ??, or conversions). @SwiftMockitoTests/CaptureTests.swift"])
        #expect(mock.runtime.stubsSnapshot(member: "cached(id:)").isEmpty)
    }

    @Test func answersWhoseResultTypeDiffersFromTheMemberAreRejected() {
        let expected = "when: the closure evaluates to Optional<String> but SampleMock.fetch(id:) returns String; put only the member call in the closure (no try?, ??, or conversions). @SwiftMockitoTests/CaptureTests.swift"
        #expect(failures {
            when { try? await mock.fetch(id: "1") }.thenAnswer { (id: String) -> String? in id }
        } == [expected])
        #expect(failures {
            when { try? await mock.fetch(id: "1") }.thenAnswer { (id: String) async -> String? in id }
        } == [expected])
        #expect(mock.runtime.stubsSnapshot(member: "fetch(id:)").isEmpty)
    }

    @Test func matchingTypeStillInstallsAndAnswers() async throws {
        when { try await mock.fetch(id: "1") }.thenAnswer { (id: String) -> String in "got \(id)" }
        #expect(try await mock.fetch(id: "1") == "got 1")
    }

    @Test func unsupportedArgumentFailsStubbingButRealCallsWork() {
        let expected = UnsupportedExactMatchingError(member: "SampleMock.render(_:)", position: 0,
                                                     typeName: String(reflecting: Opaque.self)).description
        #expect(failures { when(mock.render(Opaque())).thenReturn(()) } == ["\(expected) @SwiftMockitoTests/CaptureTests.swift"])
        mock.render(Opaque())
        #expect(mock.runtime.callsSnapshot().count == 1)
    }

    @Test func parallelTestsHaveIsolatedCaptures() async {
        let mocks = (0..<50).map { _ in SampleMock() }
        await withTaskGroup(of: Void.self) { group in
            for (i, mock) in mocks.enumerated() {
                group.addTask {
                    when(mock.cached(id: "\(i)")).thenReturn("v\(i)")
                    #expect(mock.cached(id: "\(i)") == "v\(i)")
                }
            }
        }
        for mock in mocks {
            #expect(mock.runtime.callsSnapshot().count == 1)
        }
    }

    @Test func captureContextDoesNotLeakAcrossAwait() async throws {
        when { try await mock.fetch(id: "1") }.thenReturn("one")
        await Task.yield()
        #expect(Capture.current == nil)
        #expect(try await mock.fetch(id: "1") == "one")
    }

    @Test func suspendingCaptureExpressionIsMisuse() {
        #expect(failures {
            when {
                await Task.yield()
                return try await mock.fetch(id: "1")
            }.thenReturn("x")
        } == ["when: the expression suspended before reaching a mock call. Keep only the mock call inside the closure; a mock of a global-actor protocol must be used from a test isolated to that actor. @SwiftMockitoTests/CaptureTests.swift"])
    }

    @Test func suspendedExpressionIsAlwaysReported() {
        // The body parks on a continuation that is resumed only after `when` returned, so it
        // always suspends (`Task.yield` may not) and always finishes after `captureAll` gave up.
        let gate = Gate()
        let box = MessageBox()
        Reporter.$sink.withValue({ message, _ in box.append(message) }) {
            for _ in 0..<300 {
                when {
                    await gate.wait()
                    return try await mock.fetch(id: "1")
                }.thenReturn("x")
                gate.openAll()
            }
        }
        #expect(box.messages.count == 300)
        #expect(box.messages.allSatisfy { $0.contains("suspended before reaching a mock call") })
        #expect(mock.runtime.stubsSnapshot(member: "fetch(id:)").isEmpty)
    }

    // Resolved D1: `nonisolated(nonsending)` async members keep MainActor closures synchronous.
    @MainActor @Test func mainActorTestCapturesAsyncMember() async throws {
        when { try await mock.fetch(id: "7") }.thenReturn("main")
        #expect(try await mock.fetch(id: "7") == "main")
    }

    @Test func whenOutsideVerifyInOrderStillSignals() {
        // `continuesAfterRecord` is false here, so the throwing member throws after recording,
        // and `when` sees exactly one call.
        #expect(Capture.continuesAfterRecord == false)
        #expect(failures { when { try mock.save("x") }.thenThrow(SampleError()) }.isEmpty)
    }
}

/// Parks `wait()` callers until `openAll()`.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in lock.withLock { waiters.append(continuation) } }
    }

    func openAll() {
        let parked = lock.withLock { let all = waiters; waiters = []; return all }
        for continuation in parked { continuation.resume() }
    }
}
