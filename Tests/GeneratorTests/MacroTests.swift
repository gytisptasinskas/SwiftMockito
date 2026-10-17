import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiftMockitoMacros

final class MacroTests: XCTestCase {
    func testExpandsToNothing() {
        assertMacroExpansion(
            """
            @GenerateMock(Client.self, Catalog.self)
            enum Mocks {}
            """,
            expandedSource: """
            enum Mocks {}
            """,
            macros: ["GenerateMock": GenerateMockMacro.self]
        )
    }
}
