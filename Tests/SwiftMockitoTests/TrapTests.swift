import Testing
@testable import SwiftMockito

/// A type with no built-in dummy, so only a `dummy:` builder or `provideDummy` can make one.
private struct Thing: Equatable { let value: Int }

/// A missing stub fails the test it happens in and returns a dummy, so the rest of the run continues.
@Suite struct MissingStubTests {
    @Test func unstubbedValueCallFailsAndReturnsBuiltInDummy() {
        let box = MessageBox()
        let mock = Harness()
        let count: Int = Reporter.$sink.withValue({ message, _ in box.append(message) }) {
            mock.runtime.invoke("count", key: [])
        }
        #expect(count == 0)
        #expect(box.messages.count == 1)
        #expect(box.messages.first?.contains("Harness.count") == true)
    }

    @Test func unstubbedValueCallUsesTheGeneratedDummy() {
        let box = MessageBox()
        let mock = Harness()
        let thing: Thing = Reporter.$sink.withValue({ message, _ in box.append(message) }) {
            mock.runtime.invoke("thing", key: [], dummy: { Thing(value: 7) })
        }
        #expect(thing == Thing(value: 7))
        #expect(box.messages.count == 1)
    }

    @Test func unstubbedAsyncValueCallFailsAndReturnsDummy() async {
        let box = MessageBox()
        let mock = Harness()
        let thing: Thing = await Reporter.$sink.withValue({ message, _ in box.append(message) }) {
            await mock.runtime.invoke("thing", key: [], dummy: { Thing(value: 3) })
        }
        #expect(thing == Thing(value: 3))
        #expect(box.messages.count == 1)
    }

    @Test func unstubbedValueCallWithNoDummyStillTraps() async {
        await #expect(processExitsWith: .failure) {
            let mock = Harness()
            let _: Thing = mock.runtime.invoke("thing", key: [])
        }
    }
}

/// An unstubbed member that takes a callback never calls it, so code waiting for the callback hangs.
/// The mock warns about it (without failing the test, since "verify it was called" needs no stub).
@Suite struct UnstubbedCallbackTests {
    @Test func unstubbedCallbackMemberWarns() {
        let warnings = MessageBox()
        let failures = MessageBox()
        let mock = Harness()
        Reporter.$warningSink.withValue({ message, _ in warnings.append(message) }) {
            Reporter.$sink.withValue({ message, _ in failures.append(message) }) {
                let completion: @Sendable (Int) -> Void = { _ in }
                let _: Void = mock.runtime.invoke("load(completion:)", key: [], args: completion, callbacks: ["completion"])
            }
        }
        #expect(failures.messages.isEmpty)
        #expect(warnings.messages == [
            "Harness.load(completion:) has no stub, so its `completion` callback is never called; code that waits for it will hang. Stub it with thenAnswer and call the callback."
        ])
    }

    @Test func stubbedCallbackMemberDoesNotWarn() {
        let warnings = MessageBox()
        let mock = Harness()
        stub(mock.runtime, "load(completion:)", key: [], argumentTypes: (@Sendable (Int) -> Void).self, returning: Void.self)
            .thenAnswer { (completion: @escaping @Sendable (Int) -> Void) in completion(1) }
        Reporter.$warningSink.withValue({ message, _ in warnings.append(message) }) {
            let _: Void = mock.runtime.invoke("load(completion:)", key: [], args: { @Sendable (_: Int) in }, callbacks: ["completion"])
        }
        #expect(warnings.messages.isEmpty)
    }

    @Test func unstubbedVoidMemberWithoutCallbacksDoesNotWarn() async {
        let warnings = MessageBox()
        let mock = Harness()
        await Reporter.$warningSink.withValue({ message, _ in warnings.append(message) }) {
            let _: Void = await mock.runtime.invoke("ping()", key: [])
        }
        #expect(warnings.messages.isEmpty)
    }

    @Test func unstubbedThrowingCallbackMemberWarns() throws {
        let warnings = MessageBox()
        let mock = Harness()
        try Reporter.$warningSink.withValue({ message, _ in warnings.append(message) }) {
            let _: Void = try mock.runtime.invokeThrowing("send(done:)", key: [], args: { @Sendable in }, callbacks: ["done"])
        }
        #expect(warnings.messages.count == 1)
    }
}
