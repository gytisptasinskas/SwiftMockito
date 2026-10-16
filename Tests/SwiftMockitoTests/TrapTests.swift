import Testing
@testable import SwiftMockito

@Suite struct TrapTests {
    @Test func unstubbedNonThrowingValueCallTraps() async {
        await #expect(processExitsWith: .failure) {
            let mock = Harness()
            let _: Int = mock.runtime.invoke("count", key: [])
        }
    }
}
