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
