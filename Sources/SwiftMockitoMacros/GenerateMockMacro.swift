import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// A marker only. A macro cannot see the protocol's body, so the build plugin
/// reads `@GenerateMock(P.self)` from the source and generates `MockP`.
public struct GenerateMockMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

@main
struct SwiftMockitoMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [GenerateMockMacro.self]
}
