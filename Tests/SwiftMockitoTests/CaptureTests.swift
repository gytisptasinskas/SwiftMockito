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

    func failures(_ body: () async -> Void) async -> [String] {
        let box = MessageBox()
        await Reporter.$sink.withValue({ message, site in box.append("\(message) @\(site.fileID)") }, operation: body)
        return box.messages
    }

    @Test func captureNeverDispatches() async {
        await when { try await mock.fetch(id: "42") }.thenThrow(SampleError())
        when(mock.cached(id: "42")).thenReturn("x")
        #expect(mock.runtime.callsSnapshot().isEmpty)
    }

    @Test func asyncThrowingMemberIsCapturedWithAwait() async throws {
        await when { try await mock.fetch(id: "42") }.thenReturn("user")
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

    @Test func stubWhoseClosureTypeDiffersFromTheMemberIsRejected() async {
        #expect(await failures {
            await when { try? await mock.fetch(id: "1") }.thenReturn(nil)
        } == ["when: the closure evaluates to Optional<String> but SampleMock.fetch(id:) returns String; put only the member call in the closure (no try?, ??, or conversions). @SwiftMockitoTests/CaptureTests.swift"])
        #expect(mock.runtime.stubsSnapshot(member: "fetch(id:)").isEmpty)
    }

    @Test func syncStubWhoseClosureTypeDiffersFromTheMemberIsRejected() {
        #expect(failures {
            when(mock.cached(id: "1") ?? "x").thenReturn("y")
        } == ["when: the closure evaluates to String but SampleMock.cached(id:) returns Optional<String>; put only the member call in the closure (no try?, ??, or conversions). @SwiftMockitoTests/CaptureTests.swift"])
        #expect(mock.runtime.stubsSnapshot(member: "cached(id:)").isEmpty)
    }

    @Test func answersWhoseResultTypeDiffersFromTheMemberAreRejected() async {
        let expected = "when: the closure evaluates to Optional<String> but SampleMock.fetch(id:) returns String; put only the member call in the closure (no try?, ??, or conversions). @SwiftMockitoTests/CaptureTests.swift"
        #expect(await failures {
            await when { try? await mock.fetch(id: "1") }.thenAnswer { (id: String) -> String? in id }
        } == [expected])
        #expect(await failures {
            await when { try? await mock.fetch(id: "1") }.thenAnswer { (id: String) async -> String? in id }
        } == [expected])
        #expect(mock.runtime.stubsSnapshot(member: "fetch(id:)").isEmpty)
    }

    @Test func matchingTypeStillInstallsAndAnswers() async throws {
        await when { try await mock.fetch(id: "1") }.thenAnswer { (id: String) -> String in "got \(id)" }
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
        await when { try await mock.fetch(id: "1") }.thenReturn("one")
        await Task.yield()
        #expect(Capture.current == nil)
        #expect(try await mock.fetch(id: "1") == "one")
    }

    /// The capture is task-local, so the expression may suspend before it reaches the mock.
    @Test func suspendingBeforeTheMockCallIsFine() async throws {
        #expect(await failures {
            await when {
                await Task.yield()
                return try await mock.fetch(id: "1")
            }.thenReturn("x")
        }.isEmpty)
        #expect(try await mock.fetch(id: "1") == "x")
    }

    /// Stubbing and verifying from inside a custom actor instance works, in every form.
    @Test func worksInsideACustomActor() async throws {
        let owner = MockOwner(mock: mock)
        #expect(await owner.stubAndCall() == ["cached", "fetched"])
        verify(mock.cached(id: "1")).called(1)
    }

    // Resolved D1: `nonisolated(nonsending)` async members keep MainActor closures synchronous.
    @MainActor @Test func mainActorTestCapturesAsyncMember() async throws {
        await when { try await mock.fetch(id: "7") }.thenReturn("main")
        #expect(try await mock.fetch(id: "7") == "main")
    }

    @Test func whenOutsideVerifyInOrderStillSignals() {
        // `continuesAfterRecord` is false here, so the throwing member throws after recording,
        // and `when` sees exactly one call.
        #expect(Capture.continuesAfterRecord == false)
        #expect(failures { when { try mock.save("x") }.thenThrow(SampleError()) }.isEmpty)
    }
}

/// Uses the mock from a custom actor's isolation.
private actor MockOwner {
    let mock: SampleMock
    init(mock: SampleMock) { self.mock = mock }

    func stubAndCall() async -> [String] {
        when(mock.cached(id: "1")).thenReturn("cached")
        await when { try await mock.fetch(id: "1") }.thenReturn("fetched")
        let fetched = (try? await mock.fetch(id: "1")) ?? "missing"
        await verify { try await mock.fetch(id: "1") }.called(1)
        return [mock.cached(id: "1") ?? "missing", fetched]
    }
}
