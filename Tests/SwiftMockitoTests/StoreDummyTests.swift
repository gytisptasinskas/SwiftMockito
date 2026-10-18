import Foundation
import Testing
@testable import SwiftMockito

private final class RecordingLogger: Logger {
    var level: Int { 1 }
    func log(_ message: String) {}
}

@Suite struct StoreDummyTests {
    let store = MockStore()

    @Test func synthesizedDummiesLetEveryShapeBeRecorded() throws {
        when(store.profile()).thenReturn(Profile(user: .fixture, tags: ["a"], score: 1))
        when(store.status()).thenReturn(.inactive)
        when(store.session()).thenReturn(Session(id: UUID()))
        when(store.logger()).thenReturn(RecordingLogger())
        when(store.pair()).thenReturn((1, "x"))
        when(store.result()).thenReturn(.failure(ClientError.offline))

        #expect(store.profile().tags == ["a"])
        #expect(store.status() == .inactive)
        #expect(store.logger().level == 1)   // the trapping protocol dummy never reached here
        #expect(store.pair() == (1, "x"))
        #expect(throws: ClientError.offline) { try store.result().get() }
    }

    /// The generated mock hands its synthesized dummy to the runtime, which returns it after failing the test.
    @Test func unstubbedCallReturnsTheGeneratedDummy() {
        var status: Status?
        withKnownIssue {
            status = MockStore().status()
        } matching: { issue in
            issue.description.contains("MockStore.status()")
        }
        #expect(status == .active(since: Date(timeIntervalSince1970: 0)))
    }
}
