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
