import Testing
@testable import SwiftMockito

private struct Boom: Error, Equatable {}

/// Its `==` re-enters the runtime, which deadlocks if keys are compared under the runtime lock.
private struct Reentrant: Equatable {
    let runtime: MockRuntime
    static func == (lhs: Self, rhs: Self) -> Bool {
        _ = lhs.runtime.callsSnapshot()
        return true
    }
}

/// Non-`Sendable` and reachable only from the main actor, so passing it onward must stay on that actor.
private final class PlainBox { var n = 0 }
private enum MainActorBoxes { @MainActor static let shared = PlainBox() }

@Suite struct RuntimeTests {
    let mock = Harness()
    var runtime: MockRuntime { mock.runtime }

    func failures(_ body: () -> Void) -> [String] {
        let box = MessageBox()
        Reporter.$sink.withValue({ message, _ in box.append(message) }, operation: body)
        return box.messages
    }

    @Test func returnsStubbedValueForExactKey() {
        stub(runtime, "cached(id:)", key: [arg("42")], argumentTypes: String.self, returning: String?.self)
            .thenReturn("hit")
        let value: String? = runtime.invoke("cached(id:)", key: [arg("42")], args: "42")
        #expect(value == "hit")
    }

    @Test func newestMatchingStubWins() {
        stub(runtime, "name", key: [], argumentTypes: Void.self, returning: String.self).thenReturn("old")
        stub(runtime, "name", key: [], argumentTypes: Void.self, returning: String.self).thenReturn("new")
        let value: String = runtime.invoke("name", key: [])
        #expect(value == "new")
    }

    @Test func sequentialReturnsRepeatTheLast() {
        stub(runtime, "next", key: [], argumentTypes: Void.self, returning: Int.self).thenReturn(1, 2, 3)
        let values: [Int] = (0..<5).map { _ in runtime.invoke("next", key: []) }
        #expect(values == [1, 2, 3, 3, 3])
    }

    @Test func thenThrowThrowsFromThrowingMember() {
        stub(runtime, "save(_:)", key: [arg(1)], argumentTypes: Int.self, effects: .throwing, returning: Void.self)
            .thenThrow(Boom())
        #expect(throws: Boom()) {
            try runtime.invokeThrowing("save(_:)", key: [arg(1)], args: 1) as Void
        }
    }

    @Test func answerReceivesTypedArgumentsIncludingCallbacks() {
        stub(runtime, "load(id:completion:)", key: [arg("42")],
             argumentTypes: (String, (Result<String, any Error>) -> Void).self, returning: Void.self)
            .thenAnswer { (id: String, completion: @escaping (Result<String, any Error>) -> Void) in
                completion(.success("user-\(id)"))
            }
        var delivered: String?
        let completion: (Result<String, any Error>) -> Void = { delivered = try? $0.get() }
        runtime.invoke("load(id:completion:)", key: [arg("42")], args: "42", completion) as Void
        #expect(delivered == "user-42")
    }

    @Test func asyncAnswerRunsForAsyncMember() async throws {
        stub(runtime, "fetch(id:)", key: [arg("1")], argumentTypes: String.self,
             effects: [.async, .throwing], returning: String.self)
            .thenAnswer { (id: String) async throws in
                await Task.yield()
                return "fetched-\(id)"
            }
        let value: String = try await runtime.invokeThrowing("fetch(id:)", key: [arg("1")], args: "1")
        #expect(value == "fetched-1")
    }

    @Test func asyncCallbackAnswerOnThrowingAsyncMember() async throws {
        stub(runtime, "fetch(id:done:)", key: [arg("1")], argumentTypes: (String, (String) -> Void).self,
             effects: [.async, .throwing], returning: Void.self)
            .thenAnswer { (id: String, done: @escaping (String) -> Void) async in done(id) }
        let box = MessageBox()
        let done: (String) -> Void = { box.append($0) }
        try await runtime.invokeThrowing("fetch(id:done:)", key: [arg("1")], args: "1", done) as Void
        #expect(box.messages == ["1"])
    }

    @MainActor @Test func asyncDispatchAcceptsNonSendableArgumentFromActor() async throws {
        let box = MainActorBoxes.shared
        box.n = 0
        stub(runtime, "put(_:)", key: [arg(box)], argumentTypes: PlainBox.self,
             effects: [.async, .throwing], returning: Void.self)
            .thenAnswer { (box: PlainBox) async throws in box.n += 1 }
        try await runtime.invokeThrowing("put(_:)", key: [arg(box)], args: box) as Void
        #expect(box.n == 1)
        stub(runtime, "get(_:)", key: [arg(box)], argumentTypes: PlainBox.self,
             effects: .async, returning: Int.self)
            .thenAnswer { (box: PlainBox) async in box.n }
        let value: Int = await runtime.invoke("get(_:)", key: [arg(box)], args: box)
        #expect(value == 1)
    }

    @Test func throwingCallbackAnswerStillThrows() {
        stub(runtime, "load(id:done:)", key: [arg("1")], argumentTypes: (String, (String) -> Void).self,
             effects: .throwing, returning: Void.self)
            .thenAnswer { (id: String, done: @escaping (String) -> Void) throws in
                done(id)
                throw Boom()
            }
        let box = MessageBox()
        let done: (String) -> Void = { box.append($0) }
        #expect(throws: Boom()) {
            try runtime.invokeThrowing("load(id:done:)", key: [arg("1")], args: "1", done) as Void
        }
        #expect(box.messages == ["1"])
    }

    @Test func neverFailureStubAcceptsNonThrowingCallbackAnswer() {
        let target = StubTarget(runtime: runtime, member: "run(id:done:)", key: [arg("1")],
                                argumentsType: (String, (String) -> Void).self, effects: [], site: CallSite())
        Stub<Void, Never>(target: target)
            .thenAnswer { (id: String, done: @escaping (String) -> Void) in done(id) }
        let box = MessageBox()
        let done: (String) -> Void = { box.append($0) }
        runtime.invoke("run(id:done:)", key: [arg("1")], args: "1", done) as Void
        #expect(box.messages == ["1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func equalityThatReentersTheRuntimeDoesNotDeadlock() {
        stub(runtime, "lookup(_:)", key: [arg(Reentrant(runtime: runtime))],
             argumentTypes: Reentrant.self, returning: String.self)
            .thenReturn("found")
        let value: String = runtime.invoke("lookup(_:)", key: [arg(Reentrant(runtime: runtime))],
                                           args: Reentrant(runtime: runtime))
        #expect(value == "found")
    }

    @Test func missingStubOnThrowingMemberThrowsDiagnostic() {
        stub(runtime, "fetch(id:)", key: [arg("42")], argumentTypes: String.self, effects: .throwing,
             returning: String.self, site: CallSite(fileID: "T.swift", line: 9, column: 5))
            .thenReturn("x")
        do {
            let _: String = try runtime.invokeThrowing("fetch(id:)", key: [arg("7")], args: "7")
            Issue.record("expected MissingStubError")
        } catch let error as MissingStubError {
            #expect(error.member == "fetch(id:)")
            #expect(error.arguments == ["\"7\""])
            #expect(error.configuredStubs == ["(\"42\") at T.swift:9:5"])
            #expect(error.description == """
                No stub for Harness.fetch(id:) with arguments ("7").
                Configured stubs for fetch(id:):
                  ("42") at T.swift:9:5
                Mock created at Harness.swift:1:1.
                """)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func unstubbedVoidCallIsRecordedAndReturns() {
        runtime.invoke("log(_:)", key: [arg("hi")], args: "hi") as Void
        #expect(runtime.callsSnapshot().map(\.member) == ["log(_:)"])
    }

    @Test func realCallsAreRecordedOnceInGlobalOrder() {
        let other = Harness()
        runtime.invoke("a", key: []) as Void
        other.runtime.invoke("b", key: []) as Void
        runtime.invoke("c", key: [arg(1)], args: 1) as Void
        let ids = runtime.callsSnapshot().map(\.id)
        #expect(runtime.callsSnapshot().map(\.member) == ["a", "c"])
        #expect(ids[0] < other.runtime.callsSnapshot()[0].id)
        #expect(other.runtime.callsSnapshot()[0].id < ids[1])
    }

    @Test func resetClearsStubsAndCalls() {
        stub(runtime, "next", key: [], argumentTypes: Void.self, returning: Int.self).thenReturn(1)
        runtime.invoke("log", key: []) as Void
        runtime.reset()
        #expect(runtime.callsSnapshot().isEmpty)
        #expect(runtime.stubsSnapshot(member: "next").isEmpty)
    }

    @Test func concurrentCallsAndStubbingKeepStorageConsistent() async {
        let runtime = self.runtime
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<500 {
                group.addTask {
                    if i.isMultiple(of: 10) {
                        stub(runtime, "n", key: [], argumentTypes: Void.self, returning: Int.self).thenReturn(i)
                    }
                    runtime.invoke("log(_:)", key: [arg(i)], args: i) as Void
                }
            }
        }
        #expect(runtime.callsSnapshot().count == 500)
        #expect(Set(runtime.callsSnapshot().map(\.id)).count == 500)
        #expect(runtime.stubsSnapshot(member: "n").count == 50)
    }

    @Test func answerWithWrongArgumentTypesIsReportedAtStubTime() {
        #expect(failures {
            stub(runtime, "cached(id:)", key: [arg("42")], argumentTypes: String.self, returning: String?.self)
                .thenAnswer { (id: Int) in "\(id)" }
        } == ["thenAnswer for Harness.cached(id:) takes (Int) but the member passes (String)."])
    }

    @Test func asyncAnswerOnSyncMemberIsReportedAtStubTime() {
        #expect(failures {
            stub(runtime, "cached(id:)", key: [arg("42")], argumentTypes: String.self, returning: String?.self)
                .thenAnswer { (id: String) async in id }
        } == ["thenAnswer for Harness.cached(id:) is async but the member is synchronous."])
    }

    @Test func thenThrowOnNonThrowingMemberIsReportedAtStubTime() {
        #expect(failures {
            stub(runtime, "cached(id:)", key: [arg("42")], argumentTypes: String.self, returning: String?.self)
                .thenThrow(Boom())
        } == ["thenThrow for Harness.cached(id:): the member does not throw."])
    }

    @Test func emptyThenReturnIsReported() {
        #expect(failures {
            stub(runtime, "next", key: [], argumentTypes: Void.self, returning: Int.self).thenReturn()
        } == ["thenReturn for Harness.next needs at least one value."])
    }
}
