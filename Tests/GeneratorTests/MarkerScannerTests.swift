import Foundation
import Testing
@testable import SwiftMockitoGeneratorCore

@Suite struct MarkerScannerTests {
    @Test func findsAllNamesInOrder() {
        let text = """
            @GenerateMock(Client.self)
            enum A {}
            @GenerateMock( Catalog.self ,Screen.self )
            enum B {}
            // @GenerateMock(Commented.self) is found too; the generator writes a comment-only file for it.
            """
        #expect(MarkerScanner.protocolNames(in: text) == ["Client", "Catalog", "Screen", "Commented"])
    }

    @Test func agreesWithTheParserOnRealMarkers() {
        let text = "@GenerateMock(Client.self, Catalog.self)\nenum Mocks {}\n"
        let parsed = SourceIndex([SourceInput(path: "/m", module: "T", text: text)]).markers(in: ["/m"]).map(\.protocolName)
        #expect(MarkerScanner.protocolNames(in: text) == parsed)
    }

    @Test func ignoresProseWithAnUnterminatedMarkerAndFindsTheRealOne() {
        let text = """
            /// Mark protocols with @GenerateMock( and a list
            @GenerateMock(Client.self)
            enum Mocks {}
            """
        #expect(MarkerScanner.protocolNames(in: text) == ["Client"])
        let parsed = SourceIndex([SourceInput(path: "/m", module: "T", text: text)]).markers(in: ["/m"]).map(\.protocolName)
        #expect(MarkerScanner.protocolNames(in: text) == parsed)
    }

    @Test func findsMultiLineMultiNameMarkers() {
        let text = "@GenerateMock(\n    Client.self,\n    Catalog.self\n)\nenum Mocks {}\n"
        #expect(MarkerScanner.protocolNames(in: text) == ["Client", "Catalog"])
        let parsed = SourceIndex([SourceInput(path: "/m", module: "T", text: text)]).markers(in: ["/m"]).map(\.protocolName)
        #expect(MarkerScanner.protocolNames(in: text) == parsed)
    }

    @Test func keepsQualifiedNames() {
        #expect(MarkerScanner.protocolNames(in: "@GenerateMock(App.Client.self)") == ["App.Client"])
    }

    @Test func acceptsATrailingComma() {
        for text in ["@GenerateMock(Client.self, )\nenum Mocks {}\n", "@GenerateMock(\n    Client.self,\n    Catalog.self,\n)\nenum Mocks {}\n"] {
            let parsed = SourceIndex([SourceInput(path: "/m", module: "T", text: text)]).markers(in: ["/m"]).map(\.protocolName)
            #expect(!parsed.isEmpty)
            #expect(MarkerScanner.protocolNames(in: text) == parsed)
        }
        #expect(MarkerScanner.protocolNames(in: "@GenerateMock(,)") == [])
        #expect(MarkerScanner.protocolNames(in: "@GenerateMock()") == [])
    }

    @Test func findsTheQualifiedAttributeLikeTheParser() {
        let text = """
            @SwiftMockito.GenerateMock(Client.self)
            enum Mocks {}
            @Other.GenerateMock(Catalog.self)
            enum Others {}
            @GenerateMockery(Screen.self)
            enum Mockery {}
            """
        let parsed = SourceIndex([SourceInput(path: "/m", module: "T", text: text)]).markers(in: ["/m"]).map(\.protocolName)
        #expect(parsed == ["Client"])
        #expect(MarkerScanner.protocolNames(in: text) == parsed)
    }

    @Test func pluginCopyIsIdentical() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let library = try String(contentsOf: root.appending(path: "Sources/SwiftMockitoGeneratorCore/MarkerScanner.swift"), encoding: .utf8)
        let plugin = try String(contentsOf: root.appending(path: "Plugins/SwiftMockitoPlugin/MarkerScanner.swift"), encoding: .utf8)
        #expect(library == plugin)
    }
}
