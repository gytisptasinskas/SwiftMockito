import Testing
@testable import SwiftMockito

@MainActor
@Suite struct ScreenAcceptanceTests {
    let screen = MockScreen()

    @Test func globalActorMockWorks() {
        when(screen.isVisible).thenReturn(true)
        screen.render(title: "Home")
        #expect(screen.isVisible)
        verify(screen.render(title: "Home")).called(1)
    }
}
