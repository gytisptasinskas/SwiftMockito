import Testing
@testable import SwiftMockito

@Suite struct ShapesAcceptanceTests {
    let shapes = MockShapes()

    @Test func everyDummyBuildsWhileRecording() {
        when(shapes.observed()).thenReturn(Observed(count: 1, label: "o"))
        when(shapes.pair()).thenReturn(Pair(a: 1, b: 2))
        when(shapes.defaults()).thenReturn(Defaults(name: "d"))
        when(shapes.payload()).thenReturn(.named(id: 3))
        when(shapes.subBox()).thenReturn(SubBox(x: 4))

        #expect(shapes.observed().count == 1)
        #expect(shapes.pair().b == 2)
        #expect(shapes.defaults().name == "d")
        if case .named(let id) = shapes.payload() { #expect(id == 3) } else { Issue.record("payload") }
        #expect(shapes.subBox().x == 4)
    }
}
