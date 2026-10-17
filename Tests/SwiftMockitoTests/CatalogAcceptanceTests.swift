import Foundation
import Testing
@testable import SwiftMockito

@Suite struct CatalogAcceptanceTests {
    let catalog = MockCatalog()

    @Test func subscriptGetAndSet() {
        when(catalog[1]).thenReturn("one")
        catalog[2] = "two"
        #expect(catalog[1] == "one")
        verify { catalog[2] = "two" }.called(1)
    }

    @Test func overloadsAreSeparateMembers() {
        when(catalog.item(id: 1)).thenReturn("int")
        when(catalog.item(id: "1")).thenReturn("string")
        #expect(catalog.item(id: 1) == "int")
        #expect(catalog.item(id: "1") == "string")
    }

    @Test func genericTypeIsPartOfTheKey() throws {
        when { try catalog.decode(Data(), as: Int.self) }.thenReturn(7)
        when { try catalog.decode(Data(), as: String.self) }.thenReturn("seven")
        #expect(try catalog.decode(Data(), as: Int.self) == 7)
        #expect(try catalog.decode(Data(), as: String.self) == "seven")
        catalog.store(1)
        verifyNever(catalog.store(Int64(1)))
        verify(catalog.store(1)).called(1)
    }

    @Test func classArgumentsMatchByIdentity() {
        let a = Reference(), b = Reference()
        when(catalog.describe(a)).thenReturn("a")
        #expect(catalog.describe(a) == "a")
        verifyNever(catalog.describe(b))
    }

    @Test func tupleArgumentsMatchByValue() {
        catalog.tag((1, "x"))
        verify(catalog.tag((1, "x"))).called(1)
    }

    @Test func optionalClosureIsLeftOutOfTheKey() {
        catalog.notify(nil)
        verify(catalog.notify({})).called(1)
    }
}
