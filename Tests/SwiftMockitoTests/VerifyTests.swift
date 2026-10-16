import Testing
@testable import SwiftMockito

@Suite struct VerifyTests {
    let mock = SampleMock()

    /// An unstubbed non-`Void` member traps (Task 7), so the members these tests call get stubs first.
    init() {
        when(mock.cached(id: "1")).thenReturn(nil)
        when(mock.cached(id: "42")).thenReturn(nil)
    }

    func failures(_ body: () -> Void) -> [String] {
        let box = MessageBox()
        Reporter.$sink.withValue({ message, _ in box.append(message) }, operation: body)
        return box.messages
    }

    @Test func verifyPassesAndConsumes() {
        _ = mock.cached(id: "42")
        #expect(failures { verify(mock.cached(id: "42")).called(1) }.isEmpty)
        #expect(failures { verify(mock.cached(id: "42")) } == [
            "verify: expected at least 1 unverified call to SampleMock.cached(id:) with (\"42\"), found 0.\nRecorded calls to cached(id:): (\"42\") [verified]"
        ])
    }

    @Test func calledCounts() {
        for _ in 0..<3 { _ = mock.cached(id: "1") }
        #expect(failures { verify(mock.cached(id: "1")).called(atLeast: 2) }.isEmpty)
        for _ in 0..<3 { _ = mock.cached(id: "1") }
        #expect(failures { verify(mock.cached(id: "1")).called(atMost: 3) }.isEmpty)
        for _ in 0..<3 { _ = mock.cached(id: "1") }
        #expect(failures { verify(mock.cached(id: "1")).called(2) } == [
            "verify: expected exactly 2 calls to SampleMock.cached(id:) with (\"1\"), found 3."
        ])
    }

    @Test func zeroMatchesReportsOnceEvenWithCalled() {
        #expect(failures { verify(mock.cached(id: "9")).called(1) }.count == 1)
    }

    @Test func verifyNeverCountsVerifiedCallsToo() {
        _ = mock.cached(id: "1")
        verify(mock.cached(id: "1"))
        #expect(failures { verifyNever(mock.cached(id: "1")) } == [
            "verifyNever: expected no calls to SampleMock.cached(id:) with (\"1\"), found 1."
        ])
        #expect(failures { verifyNever { try mock.save("x") } }.isEmpty)
    }

    @Test func noMoreInteractions() {
        _ = mock.cached(id: "1")
        try? mock.save("a")
        verify(mock.cached(id: "1"))
        #expect(failures { verifyNoMoreInteractions(mock) } == [
            "verifyNoMoreInteractions: SampleMock has unverified calls: save(_:) (\"a\")"
        ])
        verify { try mock.save("a") }
        #expect(failures { verifyNoMoreInteractions(mock) }.isEmpty)
    }

    @Test func resetClearsStubsAndCalls() {
        when(mock.cached(id: "1")).thenReturn("x")
        _ = mock.cached(id: "1")
        reset(mock)
        #expect(failures { verifyNever(mock.cached(id: "1")) }.isEmpty)
        #expect(mock.runtime.stubsSnapshot(member: "cached(id:)").isEmpty)
    }

    @Test func verifyWithUnsupportedArgumentFails() {
        mock.render(Opaque())
        #expect(failures { verify(mock.render(Opaque())) } == [UnsupportedExactMatchingError(
            member: "SampleMock.render(_:)", position: 0,
            typeName: String(reflecting: Opaque.self)).description])
    }
}
