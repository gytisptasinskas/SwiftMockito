import Testing
@testable import SwiftMockito

@Suite struct EdgeAcceptanceTests {
    let edge = MockEdge()

    @Test func variadicArgumentsMatchAsArray() {
        edge.log("a", 1, 2)
        verify(edge.log("a", 1, 2)).called(1)
        verifyNever(edge.log("a", 1))
    }

    @Test func keywordAndReservedParameterNames() {
        when(edge.find(for: "x")).thenReturn(7)
        #expect(edge.find(for: "x") == 7)
        edge.reserved(runtime: 1, capture: 2)
        verify(edge.reserved(runtime: 1, capture: 2)).called(1)
    }

    @Test func functionTypedReturnUsesClosureDummyOnlyWhileRecording() {
        var seen = 0
        when(edge.handler()).thenReturn({ seen = $0 })
        edge.handler()(5)
        #expect(seen == 5)
    }

    @Test func optionalFunctionPropertyAndIUOReturn() {
        when(edge.transform).thenReturn({ $0.uppercased() })
        #expect(edge.transform?("a") == "A")
        when(edge.legacy()).thenReturn("l")
        #expect(edge.legacy() == "l")
    }
}
