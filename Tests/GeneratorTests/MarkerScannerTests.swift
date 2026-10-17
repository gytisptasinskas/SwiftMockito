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

    @Test func pluginCopyIsIdentical() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let library = try String(contentsOf: root.appending(path: "Sources/SwiftMockitoGeneratorCore/MarkerScanner.swift"), encoding: .utf8)
        let plugin = try String(contentsOf: root.appending(path: "Plugins/SwiftMockitoPlugin/MarkerScanner.swift"), encoding: .utf8)
        #expect(library == plugin)
    }
}
